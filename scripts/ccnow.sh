#!/usr/bin/env bash
# ccnow — Print the currently-active provider.
# Exit code: 0 if set, 1 if not set.
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

if [[ -f "$CCPOD_CURRENT_FILE" ]]; then
  cat "$CCPOD_CURRENT_FILE"
else
  echo "unset"
  exit 1
fi
