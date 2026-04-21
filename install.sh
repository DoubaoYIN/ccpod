#!/usr/bin/env bash
# install.sh — install ccpod commands into the user's PATH
#
# Creates three symlinks in ~/.local/bin pointing into this repo:
#   ccuse, ccstart, ccnow
# Copies provider templates into ~/.claude/providers/ (without overwriting
# existing user configs).
#
# Idempotent — safe to run multiple times.

set -euo pipefail

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${CCPOD_BIN_DIR:-$HOME/.local/bin}"
CLAUDE_DIR="${CCPOD_CLAUDE_DIR:-$HOME/.claude}"
PROV_DIR="$CLAUDE_DIR/providers"

info()  { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m⚠\033[0m  %s\n' "$*" >&2; }
die()   { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ─── 1. Deps check ─────────────────────────────────────────
command -v jq      >/dev/null 2>&1 || die "缺少 jq (安装: brew install jq)"
command -v python3 >/dev/null 2>&1 || die "缺少 python3"

# ─── 2. Ensure directories exist ───────────────────────────
mkdir -p "$BIN_DIR" "$PROV_DIR"

# ─── 3. Link scripts ───────────────────────────────────────
link_cmd() {
  local name="$1"
  local src="$REPO_DIR/scripts/${name}.sh"
  local dst="$BIN_DIR/$name"

  [[ -f "$src" ]] || die "缺少脚本: $src"

  if [[ -L "$dst" ]]; then
    local current
    current="$(readlink "$dst")"
    if [[ "$current" == "$src" ]]; then
      info "已链接: $dst"
      return
    fi
    warn "覆盖旧链接: $dst → $current"
    rm -f "$dst"
  elif [[ -e "$dst" ]]; then
    die "$dst 已存在且不是符号链接，请手动删除后再试"
  fi

  ln -s "$src" "$dst"
  info "链接: $dst → $src"
}

for cmd in ccuse ccstart ccnow ccgo; do
  link_cmd "$cmd"
done

# ─── 4. Copy provider templates (never overwrite) ──────────
copy_provider() {
  local src_name="$1"
  local dst_name="$2"
  local src="$REPO_DIR/providers/$src_name"
  local dst="$PROV_DIR/$dst_name"

  [[ -f "$src" ]] || die "缺少模板: $src"

  if [[ -f "$dst" ]]; then
    info "保留现有: $dst"
  else
    cp "$src" "$dst"
    info "复制: $dst"
  fi
}

copy_provider "official.json"           "official.json"
copy_provider "easyclaude.example.json" "easyclaude.json"

# ─── 5. PATH check ─────────────────────────────────────────
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR 不在 \$PATH 中，请添加: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

# ─── 6. Reminder about real key ────────────────────────────
if grep -q "REPLACE_WITH_YOUR_KEY" "$PROV_DIR/easyclaude.json" 2>/dev/null; then
  echo
  warn "请编辑 $PROV_DIR/easyclaude.json 填入真实 ANTHROPIC_API_KEY"
fi

echo
info "ccpod 安装完成。试试: ccuse --list"
