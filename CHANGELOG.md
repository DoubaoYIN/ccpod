# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Breaking**: `ccuse` no longer modifies `settings.json`. It now only sets
  the default provider preference. Each CC window gets its own provider via
  env injection at launch time (per-window isolation).
- `ccgo` and `ccstart` inject provider env vars directly into the `claude`
  process instead of writing to the global `settings.json`.

### Added
- Session registry (`~/.claude/ccpod-sessions.json`): tracks all running CC
  instances with PID, TTY, provider, project, and terminal info.
- Menu bar launcher panel: select provider + project + terminal → opens a
  new terminal window with CC already running.
- Running sessions list in menu bar: shows all active CC windows, with
  one-click provider switching (auto `/quit` + relaunch).
- Terminal adapter system: Ghostty (native AppleScript) and Terminal.app
  support, extensible for iTerm2.
- `get_provider_env`, `register_session`, `unregister_session`,
  `cleanup_dead_sessions`, `detect_terminal` helpers in `common.sh`.

### Fixed
- Provider env leakage: switching from easyclaude to official in the same
  shell now properly unsets `ANTHROPIC_*` variables.

## [0.1.0] — 2026-04-21

### Added
- Initial repository scaffold (Phase 1)
- Core shell commands: `ccuse`, `ccstart`, `ccnow`
- Shared helpers under `scripts/lib/`
- Provider config templates: `official.json`, `easyclaude.example.json`
- MIT license, .gitignore, README skeleton
- `install.sh` / `uninstall.sh` — symlink-based installer, idempotent, honors
  `CCPOD_BIN_DIR` and `CCPOD_CLAUDE_DIR` for sandboxed installs (Phase 2)
- Status line sidecar: every `ccuse` switch writes a pre-formatted badge to
  `~/.claude/ccpod-status.txt` for any statusline tool to `cat` inline
- `ccnow --badge` / `-b` prints the formatted badge directly (Phase 3a)
- Native Swift menu bar app (`menubar/`): shows current provider, one-click
  switch, auto-refreshes when CLI changes the provider. Built via
  `menubar/build.sh` → `menubar/build/CCPod.app` (Phase 3b)
- `ccuse` now accepts unique prefixes — `ccuse off` / `ccuse easy` (Phase 4a)
- New `ccgo` command: switch provider + `cd` + launch `claude` in one shot,
  with substring fuzzy-match against recent CC projects (Phase 4a)
