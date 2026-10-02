#!/usr/bin/env bash
# Builds "Git Plus.app" into ./build from the Swift package.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product GitPlus
BIN="$(swift build -c release --show-bin-path)/GitPlus"
APP="build/Git Plus.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GitPlus"
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Git Plus.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Git Plus.app"
fi
