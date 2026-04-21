#!/usr/bin/env bash
# build.sh — compile CCPodMenuBar and wrap it in a .app bundle.
#
# Outputs: menubar/build/CCPod.app

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="CCPod"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
EXEC_NAME="CCPodMenuBar"

info() { printf '\033[32m✓\033[0m %s\n' "$*"; }

info "swift build -c release"
cd "$SCRIPT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$EXEC_NAME"
[[ -f "$BIN_PATH" ]] || { echo "找不到二进制: $BIN_PATH" >&2; exit 1; }

info "打包 $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc code sign so macOS will run it without Gatekeeper blocking.
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo
info "构建完成: $APP_DIR"
echo
echo "运行: open \"$APP_DIR\""
echo "安装: mv \"$APP_DIR\" /Applications/"
