#!/usr/bin/env bash
# ccuse — Switch between Claude Code providers
# Part of ccpod: https://github.com/<owner>/ccpod

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

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
ccuse — Set default Claude Code provider

USAGE
  ccuse <provider>       Set default provider (prefix OK)
  ccuse --list, -l       List available providers
  ccuse --help, -h       Show this help

Note: ccuse sets the default for ccstart/ccgo. It does NOT modify
settings.json. Each CC window gets its own provider via env injection.

EXAMPLES
  ccuse official         Use Anthropic Pro/Max OAuth
  ccuse off              Same as above (unique prefix)
  ccuse easyclaude       Use easyclaude relay
  ccuse easy             Same as above (unique prefix)
EOF
}

list_providers() {
  echo "Available providers:"
  local found=0
  for f in "$CCPOD_PROVIDERS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local name
    name="$(basename "$f" .json)"
    [[ "$name" == *.example ]] && continue
    local marker=""
    if [[ -f "$CCPOD_CURRENT_FILE" ]] && [[ "$(cat "$CCPOD_CURRENT_FILE")" == "$name" ]]; then
      marker=" (current)"
    fi
    echo "  - $name$marker"
    found=1
  done
  [[ $found -eq 0 ]] && echo "  (no providers installed)"
}

main() {
  case "${1:-}" in
    ""|-h|--help) usage; exit 0 ;;
    -l|--list)    list_providers; exit 0 ;;
  esac

  local name
  name="$(resolve_provider "$1")"

  [[ -d "$CCPOD_CLAUDE_DIR" ]] || mkdir -p "$CCPOD_CLAUDE_DIR"

  echo "$name" > "$CCPOD_CURRENT_FILE"
  ccpod_format_badge "$name" > "$CCPOD_STATUS_FILE"
  info "✅ 已设为默认: $name"

  # Smart-default B: remember this project's preferred provider
  if [[ -n "${CCPOD_PROJECT_DIR:-}" ]]; then
    remember_project_provider "$CCPOD_PROJECT_DIR" "$name"
  fi
}

main "$@"
