#!/usr/bin/env bash
# common.sh — shared variables and helpers for ccpod scripts
#
# This file is sourced by ccuse / ccstart / ccnow.
# Do not execute it directly.

# ─── Paths ────────────────────────────────────────────────
: "${CCPOD_CLAUDE_DIR:=$HOME/.claude}"
CCPOD_PROVIDERS_DIR="$CCPOD_CLAUDE_DIR/providers"
CCPOD_CURRENT_FILE="$CCPOD_CLAUDE_DIR/current-provider"
CCPOD_STATUS_FILE="$CCPOD_CLAUDE_DIR/ccpod-status.txt"
CCPOD_SETTINGS_FILE="$CCPOD_CLAUDE_DIR/settings.json"
CCPOD_PROJECT_MAP="$CCPOD_CLAUDE_DIR/project-providers.json"

# ─── Pre-formatted badge for statusline tools ─────────────
# Writes "<emoji> <name>" to CCPOD_STATUS_FILE. Any statusline can
# inline it via `cat ~/.claude/ccpod-status.txt`.
ccpod_format_badge() {
  case "$1" in
    official)   printf '🟢 official' ;;
    easyclaude) printf '🔵 easyclaude' ;;
    *)          printf '⚪ %s' "$1" ;;
  esac
}

# ─── Output helpers ───────────────────────────────────────
die() {
  printf '❌ %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

warn() {
  printf '⚠️  %s\n' "$*" >&2
}

# ─── Dependency check ─────────────────────────────────────
require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [[ -n "$hint" ]]; then
      die "缺少依赖: $cmd (安装: $hint)"
    else
      die "缺少依赖: $cmd"
    fi
  fi
}

# ─── Symlink-safe script directory resolution ─────────────
# Usage: SCRIPT_DIR="$(resolve_script_dir "${BASH_SOURCE[0]}")"
resolve_script_dir() {
  local src="$1"
  while [[ -L "$src" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}

# ─── Smart-default B: per-project provider memory ─────────
remember_project_provider() {
  local proj="$1"
  local prov="$2"
  require_cmd python3
  python3 - "$CCPOD_PROJECT_MAP" "$proj" "$prov" <<'PYEOF'
import json, os, sys
path, proj, prov = sys.argv[1:4]
data = {}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except Exception:
        data = {}
data[proj] = prov
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PYEOF
}

get_project_provider() {
  local proj="$1"
  [[ -f "$CCPOD_PROJECT_MAP" ]] || return 1
  require_cmd python3
  python3 - "$CCPOD_PROJECT_MAP" "$proj" <<'PYEOF'
import json, sys
path, proj = sys.argv[1:3]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(1)
if proj in data:
    print(data[proj])
else:
    sys.exit(1)
PYEOF
}
