#!/usr/bin/env bash
# ccgo — switch provider and launch Claude Code in one shot.
#   Each window gets its own provider via env injection (not settings.json).
# Part of ccpod

set -euo pipefail

SCRIPT_DIR="$(
  src="${BASH_SOURCE[0]}"
  while [[ -L "$src" ]]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
)"

source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
ccgo — 切换线路并启动 Claude Code

USAGE
  ccgo <provider>              在当前目录启动
  ccgo <provider> <project>    在最近使用过、路径含 <project> 的目录启动
  ccgo --help, -h              显示帮助

每个窗口独立：env 注入，不改 settings.json。

EXAMPLES
  ccgo easy                    easyclaude + cwd
  ccgo off                     official + cwd
  ccgo easy analytics          easyclaude + 最近含 "analytics" 的项目
  ccgo off ccpod               official + 最近含 "ccpod" 的项目
EOF
}

main() {
  case "${1:-}" in
    ""|-h|--help) usage; exit 0 ;;
  esac

  require_cmd claude "https://github.com/anthropics/claude-code"

  local name workdir
  name="$(resolve_provider "$1")"

  if [[ $# -ge 2 ]]; then
    local frag="$2"
    workdir="$(find_project_by_fragment "$frag")" \
      || die "找不到最近项目含 '$frag' (只查 ~/.claude/projects/ 里的)"
  else
    workdir="$(pwd)"
  fi
  [[ -d "$workdir" ]] || die "目录不存在: $workdir"

  # Remember this project's provider preference
  remember_project_provider "$workdir" "$name"

  # Inject provider env vars into this shell (inherited by exec claude)
  eval "$(get_provider_env "$name")"

  # Register session (cleanup stale ones first)
  cleanup_dead_sessions
  local cur_tty cur_terminal
  cur_tty="$(tty 2>/dev/null || true)"
  [[ "$cur_tty" == "not a tty" || -z "$cur_tty" ]] && cur_tty="unknown"
  cur_terminal="$(detect_terminal)"
  register_session $$ "$cur_tty" "$name" "$workdir" "$cur_terminal"

  info "✅ $name · $workdir"
  cd "$workdir"
  claude
  # claude exited (e.g. /quit) — shell stays alive for potential relaunch
}

main "$@"
