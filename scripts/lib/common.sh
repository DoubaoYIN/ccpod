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
CCPOD_SESSIONS_FILE="$CCPOD_CLAUDE_DIR/ccpod-sessions.json"

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

# ─── Provider prefix resolver ─────────────────────────────
# "off" → "official", "easy" → "easyclaude". Exact match wins first.
# Errors out if the prefix is ambiguous.
resolve_provider() {
  local q="$1"
  if [[ -f "$CCPOD_PROVIDERS_DIR/$q.json" ]]; then
    printf '%s' "$q"
    return 0
  fi
  local matches=()
  local f name
  for f in "$CCPOD_PROVIDERS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .json)"
    [[ "$name" == *.example ]] && continue
    if [[ "$name" == "$q"* ]]; then
      matches+=("$name")
    fi
  done
  case ${#matches[@]} in
    0) die "未知 provider: '$q' (运行 'ccuse --list' 查看可用)" ;;
    1) printf '%s' "${matches[0]}" ;;
    *) die "provider '$q' 不唯一，匹配到: ${matches[*]}" ;;
  esac
}

# ─── Fuzzy match against recent CC projects ──────────────
# Looks in ~/.claude/projects/ (where CC stores per-project session dirs),
# decodes the '-' encoded names back to paths, returns the most recently
# used one whose path contains $1 as a substring.
find_project_by_fragment() {
  local frag="$1"
  local d="$HOME/.claude/projects"
  [[ -d "$d" ]] || return 1
  local enc decoded
  # ls -t gives newest first; first substring match wins.
  for enc in $(ls -t1 "$d" 2>/dev/null); do
    decoded="$(echo "$enc" | sed 's|^-|/|; s|-|/|g')"
    if [[ -d "$decoded" && "$decoded" == *"$frag"* ]]; then
      printf '%s' "$decoded"
      return 0
    fi
  done
  return 1
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

# ─── Terminal detection ──────────────────────────────────
detect_terminal() {
  case "${TERM_PROGRAM:-}" in
    ghostty)       printf 'ghostty' ;;
    Apple_Terminal) printf 'terminal' ;;
    iTerm.app)     printf 'iterm2' ;;
    *)             printf '%s' "${TERM_PROGRAM:-unknown}" ;;
  esac
}

# ─── Provider env injection ──────────────────────────────
# Reads provider JSON and outputs export/unset statements.
# Always unsets ANTHROPIC_* first to prevent leakage from prior sessions
# in the same shell (critical for one-click provider switch).
# Usage: eval "$(get_provider_env easyclaude)"
get_provider_env() {
  local name="$1"
  local prov="$CCPOD_PROVIDERS_DIR/${name}.json"
  [[ -f "$prov" ]] || die "未知 provider: $name"
  require_cmd python3
  python3 - "$prov" <<'PYEOF'
import json, sys, shlex
data = json.load(open(sys.argv[1]))
env = data.get("env", {})
all_keys = {"ANTHROPIC_BASE_URL", "ANTHROPIC_API_KEY", "ANTHROPIC_API_TOKEN",
            "ANTHROPIC_AUTH_TOKEN"}
all_keys.update(env.keys())
for k in sorted(all_keys):
    if k in env and env[k]:
        print(f"export {k}={shlex.quote(env[k])}")
    else:
        print(f"unset {k} 2>/dev/null || true")
PYEOF
}

# ─── Session registry ────────────────────────────────────
# Atomic read-modify-write of ccpod-sessions.json via python3.
register_session() {
  local pid="$1" tty="$2" provider="$3" project="$4" terminal="$5"
  require_cmd python3
  python3 - "$CCPOD_SESSIONS_FILE" "$pid" "$tty" "$provider" "$project" "$terminal" <<'PYEOF'
import json, os, sys, tempfile, time
path = sys.argv[1]
rec = {
    "pid": int(sys.argv[2]),
    "tty": sys.argv[3],
    "provider": sys.argv[4],
    "project": sys.argv[5],
    "terminal": sys.argv[6],
    "started_at": time.strftime("%Y-%m-%dT%H:%M:%S")
}
data = []
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except Exception:
        data = []
data = [s for s in data if s.get("pid") != rec["pid"]]
data.append(rec)
os.makedirs(os.path.dirname(path), exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)
PYEOF
}

unregister_session() {
  local pid="$1"
  [[ -f "$CCPOD_SESSIONS_FILE" ]] || return 0
  require_cmd python3
  python3 - "$CCPOD_SESSIONS_FILE" "$pid" <<'PYEOF'
import json, os, sys, tempfile
path, pid = sys.argv[1], int(sys.argv[2])
try:
    data = json.load(open(path))
except Exception:
    sys.exit(0)
data = [s for s in data if s.get("pid") != pid]
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)
PYEOF
}

cleanup_dead_sessions() {
  [[ -f "$CCPOD_SESSIONS_FILE" ]] || return 0
  require_cmd python3
  python3 - "$CCPOD_SESSIONS_FILE" <<'PYEOF'
import json, os, sys, tempfile
path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(0)
alive = []
for s in data:
    try:
        os.kill(s["pid"], 0)
        alive.append(s)
    except OSError:
        pass
if len(alive) != len(data):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        json.dump(alive, f, indent=2)
    os.replace(tmp, path)
PYEOF
}
