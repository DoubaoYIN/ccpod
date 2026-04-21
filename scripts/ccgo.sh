#!/usr/bin/env bash
# ccgo — switch provider and launch Claude Code in one shot.
#   Supports prefix matching for both provider and project.
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

参数都支持前缀：provider 前缀 + project 子字符串模糊匹配。

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

  export CCPOD_PROJECT_DIR="$workdir"
  "$SCRIPT_DIR/ccuse.sh" "$name"

  echo ""
  info "启动 Claude Code · $workdir"
  cd "$workdir"
  exec claude
}

main "$@"
