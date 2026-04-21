# ccpod architecture

This document explains *why* ccpod is built the way it is.
For day-to-day usage, see the [README](../README.md).

## The core problem

Claude Code (CC) picks an auth method at startup by reading environment
variables from `~/.claude/settings.json`:

- **No `ANTHROPIC_*` env** → falls back to the OAuth refresh token stored
  in the keychain from `claude login`. This is the Pro/Max subscription path.
- **`ANTHROPIC_BASE_URL` + `ANTHROPIC_API_KEY` set** → routes all traffic
  through that endpoint. This is how you talk to a third-party relay.

The decision is made **at process start**. Once CC is running, flipping
these vars has no effect on the live process — CC has already chosen its
auth method.

So "switching between Pro/Max OAuth and a relay" without restarting is
fundamentally at odds with how CC reads its config. Any tool that claims
otherwise is doing one of the following.

## Three levels of "hot-switching"

### A-level — true in-process switch

The only way to genuinely redirect a running CC process is to sit between
CC and Anthropic as an HTTP proxy. CC makes requests to `localhost:<port>`,
the proxy decides per-request whether to forward to the real Anthropic
endpoint (OAuth path, refreshing the token as needed) or to the relay
(with the relay's API key), and CC never knows which one it hit.

**Why we don't ship A-level:**

1. **Anthropic's OAuth refresh flow is undocumented for third parties.**
   Implementing it means reverse-engineering the token refresh protocol
   and updating whenever Anthropic changes it. Fragile.
2. **Ban risk.** A proxy that doesn't perfectly mimic the official client's
   OAuth handshake — user-agent quirks, retry semantics, TLS fingerprint —
   is the kind of thing rate-limit heuristics flag. We will not put the
   user's subscription at risk.
3. **Complexity budget.** A hot proxy means a daemon, a TLS cert, a port
   to keep free, and a whole new failure mode. The shell-layer approach
   below covers 95% of the actual use case.

cc-switch has a "Proxy Takeover" mode that does A-level. Read their code
if you want to see what it takes — it's substantial.

### B+-level — scripted quit + auto-resume

This is what ccpod ships.

1. `ccuse <provider>` writes the provider's `env` block into
   `~/.claude/settings.json` atomically (temp file + `mv`).
2. The user quits the current CC session with `/quit`.
3. The user runs `claude --resume` (or `ccstart` does it for them), which
   picks up the JSONL session log at
   `~/.claude/projects/<encoded-path>/<session-id>.jsonl` and reconstitutes
   the full conversation.

**What survives the switch:**

- All messages, tool calls, tool results, file edits — everything that
  was written to the JSONL transcript.
- The working directory and project memory.

**What is lost:**

- Any in-flight streaming response that hadn't completed.
- Live MCP server connections (they reconnect on resume).
- In-process background tasks (nothing in CC survives process death
  regardless of tool used).

In practice: a 1-2 second blip, full conversation state intact. This is
what the "绝对不中断工作" requirement actually demands — a tool-assisted
restart, not an in-process switch.

### Known: "Auth conflict" warning when switching to a relay

When you `ccuse easy` and then launch `claude`, CC prints:

> ⚠ Auth conflict: Both a token (claude.ai) and an API key
> (ANTHROPIC_API_KEY) are set.

This is cosmetic. CC detects the OAuth token stored in the macOS
keychain (from your Pro/Max `claude login`) alongside the
`ANTHROPIC_API_KEY` we inject. It warns, but **prioritises the API key**
— you can confirm by the `API Usage Billing` label in the status line.

We cannot suppress this warning:
- There is no env var or config flag to disable the check
  ([anthropics/claude-code#9515](https://github.com/anthropics/claude-code/issues/9515),
  [#4733](https://github.com/anthropics/claude-code/issues/4733)).
- Running `claude /logout` would delete the OAuth token from the
  keychain, breaking `ccuse off` (you'd have to re-login every time you
  switch back to official).

The warning is harmless. Routing works correctly in both directions.

### B-level — manual

The user edits `settings.json` themselves, quits, re-launches. ccpod's
value over pure B-level is (a) atomic write vs hand-editing JSON, (b) a
registry of provider configs so you don't have to remember the exact env
keys, (c) per-project memory of which provider you used last.

## Data flow

```
┌────────────────┐    ccuse <name>    ┌────────────────────────┐
│ CLI user       │ ─────────────────▶ │ scripts/ccuse.sh       │
└────────────────┘                    │  1. jq merge env block │
                                      │  2. atomic rename      │
                                      │  3. write badge file   │
                                      │  4. record proj memory │
                                      └─────────┬──────────────┘
                                                │ writes
                                                ▼
                               ┌────────────────────────────────┐
                               │ ~/.claude/                     │
                               │   settings.json     (CC reads) │
                               │   current-provider  (sidecar)  │
                               │   ccpod-status.txt  (sidecar)  │
                               │   project-providers.json       │
                               └────────┬──────────────┬────────┘
                                        │              │
                        FSEvents watch  │              │  reads at startup
                                        ▼              ▼
                          ┌──────────────────┐   ┌──────────────┐
                          │ CCPod menu bar   │   │ claude CLI   │
                          │ (Swift)          │   │ (on relaunch)│
                          └──────────────────┘   └──────────────┘
```

## Why the shell layer owns the logic

The Swift menu bar app does **not** reimplement provider switching. When
the user clicks "switch to easyclaude" in the menu bar, the Swift app
literally `Process`-launches `~/.local/bin/ccuse easyclaude`.

Reasons:

- **Single source of truth.** One implementation to maintain, audit, and
  keep atomic. If we ever find a bug in the atomic-rename logic, we fix
  it once.
- **CLI is the real product.** Users who use the menu bar app still have
  `ccuse` available in scripts, shell aliases, CI, and the `ccstart`
  launcher. These need the CLI to work anyway.
- **Test surface.** Bash + jq is straightforward to smoke-test in a
  sandboxed `CCPOD_CLAUDE_DIR`. Swift testing would require a whole
  XCTest harness.

The Swift app's job is strictly UI: render state, dispatch intent.

## Provider config format

Each file under `~/.claude/providers/<name>.json` is a single JSON object
with one key, `env`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://...",
    "ANTHROPIC_API_KEY": "sk-..."
  }
}
```

To "clear" env (the official/OAuth path), the file contains `{"env": {}}`.
`ccuse` overwrites the entire `env` block in `settings.json` with this —
it does not merge. This is deliberate: leaving stale relay keys in place
when you think you're on OAuth is exactly the kind of bug that could
silently route your traffic to the wrong endpoint.

## Security posture

- **No real API keys in the repo.** `providers/easyclaude.example.json`
  has a placeholder; `install.sh` copies it to
  `~/.claude/providers/easyclaude.json` for the user to fill in.
  `.gitignore` blocks any `easyclaude.json` / `*.local.json` /
  `*.secret.json` from being staged.
- **No network calls from ccpod itself.** `ccuse`, `ccstart`, `ccnow`,
  and the menu bar app only touch local files and spawn `claude`.
- **Atomic writes** to `settings.json` prevent partial-write corruption
  if the process is killed mid-update.
- **Symlink install**: `~/.local/bin/{ccuse,ccstart,ccnow}` are symlinks
  into the repo clone, so `git pull` is the update mechanism. No
  privileged install, no system paths touched.

## What ccpod is *not*

- Not a Claude Code fork or a wrapper CLI for the model itself.
- Not a proxy. Does not intercept, inspect, or modify any API traffic.
- Not a credentials manager. The OAuth token lives in the system keychain
  where `claude login` put it; the relay API key lives in a file the user
  controls.
- Not tied to any specific relay. The provider config format is generic —
  add another `<name>.json` and `ccuse <name>` switches to it.
