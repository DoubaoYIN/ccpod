#!/usr/bin/env bash
# ccstart — Interactive launcher for Claude Code
#   Pick a recent project, pick a provider, then launch `claude`.
#   Each window gets its own provider via env injection.
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

gather_projects() {
  local d="$HOME/.claude/projects"
  [[ -d "$d" ]] || return 0
  ls -t1 "$d" 2>/dev/null | head -20 | while IFS= read -r enc; do
    local decoded
    decoded="$(echo "$enc" | sed 's|^-|/|; s|-|/|g')"
    [[ -d "$decoded" ]] && echo "$decoded"
  done
}

pick_working_dir() {
  local -a projects=()
  local line
  while IFS= read -r line; do
    projects+=("$line")
  done < <(gather_projects)

  if [[ ${#projects[@]} -eq 0 ]]; then
    read -r -p "工作目录路径: " workdir
    echo "$workdir"
    return
  fi

  echo "" >&2
  echo "最近项目:" >&2
  local i=1
  for p in "${projects[@]}"; do
    printf '  %d) %s\n' "$i" "$p" >&2
    ((i++))
  done
  printf '  %d) [手动输入]\n' "$i" >&2
  echo "" >&2

  local choice
  read -r -p "请选择 [1-$i]: " choice

  if [[ "$choice" == "$i" ]]; then
    local workdir
    read -r -p "工作目录路径: " workdir
    echo "$workdir"
  elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < i )); then
    echo "${projects[$((choice-1))]}"
  else
    die "无效选择: $choice"
  fi
}

pick_provider() {
  local default_prov="$1"
  local -a providers=()
  local f name
  for f in "$CCPOD_PROVIDERS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .json)"
    [[ "$name" == *.example ]] && continue
    providers+=("$name")
  done

  echo "" >&2
  echo "线路 (默认: $default_prov):" >&2
  local i=1
  for p in "${providers[@]}"; do
    local badge
    badge="$(ccpod_format_badge "$p")"
    printf '  %d) %s\n' "$i" "$badge" >&2
    ((i++))
  done
  local choice
  read -r -p "请选择 [1-$((i-1))/回车默认]: " choice

  case "$choice" in
    "") echo "$default_prov" ;;
    *)
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < i )); then
        echo "${providers[$((choice-1))]}"
      else
        die "无效选择: $choice"
      fi
      ;;
  esac
}

main() {
  echo "ccpod · 交互式启动"

  require_cmd claude "https://github.com/anthropics/claude-code"

  local workdir
  workdir="$(pick_working_dir)"
  [[ -n "$workdir" && -d "$workdir" ]] || die "目录不存在: $workdir"

  local default_prov
  default_prov="$(get_project_provider "$workdir" 2>/dev/null || echo official)"

  local prov
  prov="$(pick_provider "$default_prov")"

  # Remember preference
  remember_project_provider "$workdir" "$prov"

  # Inject provider env vars
  eval "$(get_provider_env "$prov")"

  # Register session
  cleanup_dead_sessions
  local cur_tty cur_terminal
  cur_tty="$(tty 2>/dev/null || true)"
  [[ "$cur_tty" == "not a tty" || -z "$cur_tty" ]] && cur_tty="unknown"
  cur_terminal="$(detect_terminal)"
  register_session $$ "$cur_tty" "$prov" "$workdir" "$cur_terminal"

  echo ""
  info "✅ $prov · $workdir"
  cd "$workdir"
  claude || true

  # claude exited — check if menu bar app left a pending switch command
  local pending="$CCPOD_CLAUDE_DIR/ccpod-pending-$$.sh"
  if [[ -f "$pending" ]]; then
    local next_cmd
    next_cmd="$(cat "$pending")"
    rm -f "$pending"
    info "🔄 自动切换: $next_cmd"
    eval "$next_cmd"
  fi
}

main "$@"
