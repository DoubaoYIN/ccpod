#!/usr/bin/env bash
# ccstart — Interactive launcher for Claude Code
#   Pick a recent project, pick a provider, then launch `claude`.
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

# Gather recent projects by decoding ~/.claude/projects/ subdir names.
# CC encodes project paths by prefixing with '-' and replacing '/' with '-'.
gather_projects() {
  local d="$HOME/.claude/projects"
  [[ -d "$d" ]] || return 0
  # List subdirs sorted by mtime (most recent first), decode, filter to existing dirs
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
  echo "" >&2
  echo "线路 (默认: $default_prov):" >&2
  echo "  1) 🟢 official  (Pro/Max OAuth)" >&2
  echo "  2) 🔵 easyclaude (relay)" >&2
  local choice
  read -r -p "请选择 [1/2/回车默认]: " choice

  case "$choice" in
    1) echo "official" ;;
    2) echo "easyclaude" ;;
    "") echo "$default_prov" ;;
    *) die "无效选择: $choice" ;;
  esac
}

main() {
  echo "ccpod · 交互式启动"

  local workdir
  workdir="$(pick_working_dir)"
  [[ -n "$workdir" && -d "$workdir" ]] || die "目录不存在: $workdir"

  local default_prov
  default_prov="$(get_project_provider "$workdir" 2>/dev/null || echo official)"

  local prov
  prov="$(pick_provider "$default_prov")"

  export CCPOD_PROJECT_DIR="$workdir"
  "$SCRIPT_DIR/ccuse.sh" "$prov"

  echo ""
  info "启动 Claude Code · $workdir"
  cd "$workdir"
  exec claude
}

main "$@"
