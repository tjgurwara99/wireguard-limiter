#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/WireGuardLimiter"
APP=build/WireGuardLimiter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WireGuardLimiter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.taj.WireGuardLimiter "$APP"
echo "Built $APP"
