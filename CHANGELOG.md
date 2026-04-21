# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
