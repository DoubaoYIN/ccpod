# ccpod

> Claude Code 多线路管理工具箱 · A toolkit for Claude Code provider switching

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Seamlessly alternate between your **Anthropic Pro/Max OAuth** subscription and
third-party relay services (e.g. easyclaude) — without losing your current
Claude Code conversation.

## Status

🚧 **Early development · v0.1**

## Planned features

- 🔀 One-command provider switching (`ccuse`)
- 📂 Smart project memory — each project remembers its last-used provider
- 🎨 macOS menu bar app (native Swift) — planned
- 🔔 Quota exhaustion alerts via CC notification hook — planned
- 📊 Status line sidecar: every switch writes a pre-formatted badge to
  `~/.claude/ccpod-status.txt` that any statusline tool can `cat` inline

## Quick start (after Phase 2 lands)

```bash
# Install
git clone https://github.com/<owner>/ccpod.git ~/Projects/ccpod
cd ~/Projects/ccpod
./install.sh

# Use
ccstart          # Interactive: pick project + provider, launch CC
ccuse official   # Direct switch to official Pro/Max OAuth
ccuse easyclaude # Direct switch to relay
ccnow            # Show current provider
```

## How it works (short version)

`ccuse` writes the chosen provider's `env` block into `~/.claude/settings.json`
using an atomic temp-file-plus-rename pattern.

- Switching to **official** clears the `env` block so CC falls back to OAuth.
- Switching to **easyclaude** injects `ANTHROPIC_BASE_URL` and
  `ANTHROPIC_API_KEY` so CC routes through the relay.

After switching, the current Claude Code session is resumed with
`claude --resume` so the conversation state is preserved (B+ level hot-switch).

For the full technical rationale — including why we don't implement true
A-level hot-switching — see [`docs/architecture.md`](docs/architecture.md).

## Status line integration

Every `ccuse` switch writes two sidecar files:

- `~/.claude/current-provider` — raw name (`official`, `easyclaude`)
- `~/.claude/ccpod-status.txt` — formatted badge (`🟢 official`, `🔵 easyclaude`)

Drop either into any statusline tool. Examples:

```bash
# In a custom statusline script
badge="$(cat ~/.claude/ccpod-status.txt 2>/dev/null)"
echo "$model · $badge"

# Or invoke ccnow directly
echo "$(ccnow --badge)"
```

## License

[MIT](LICENSE) © ccpod contributors
