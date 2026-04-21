#!/usr/bin/env bash
# uninstall.sh — remove ccpod symlinks from ~/.local/bin
#
# Leaves user data intact: ~/.claude/providers/, settings.json,
# current-provider, project-providers.json are all preserved.
#
# Only removes symlinks that point back into this repo — won't touch
# unrelated binaries that happen to share a name.

set -euo pipefail

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${CCPOD_BIN_DIR:-$HOME/.local/bin}"

info() { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⚠\033[0m  %s\n' "$*" >&2; }

unlink_cmd() {
  local name="$1"
  local dst="$BIN_DIR/$name"
  local expected="$REPO_DIR/scripts/${name}.sh"

  if [[ ! -e "$dst" && ! -L "$dst" ]]; then
    info "未安装: $name"
    return
  fi

  if [[ -L "$dst" ]]; then
    local current
    current="$(readlink "$dst")"
    if [[ "$current" == "$expected" ]]; then
      rm -f "$dst"
      info "移除: $dst"
    else
      warn "跳过 $dst — 指向其他位置 ($current)"
    fi
  else
    warn "跳过 $dst — 不是符号链接"
  fi
}

for cmd in ccuse ccstart ccnow; do
  unlink_cmd "$cmd"
done

echo
info "ccpod 已卸载。用户数据保留在 ~/.claude/"
echo "  • providers/           provider 配置"
echo "  • settings.json        Claude Code 设置"
echo "  • current-provider     当前线路记录"
echo "  • project-providers.json  每项目默认线路"
echo "如需彻底清理，请手动删除上述文件。"
