#!/bin/bash
# Build Git Plus and assemble a runnable .app bundle in build/.
#   ./build-app.sh             # build/Git Plus.app
#   ./build-app.sh --install   # also copy it to /Applications
set -euo pipefail

cd "$(dirname "$0")"

# Use regular Xcode, fall back to Xcode-beta if needed
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

if [ -n "${DEVELOPER_DIR:-}" ] && [ -x "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]; then
    SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
else
    SWIFT="$(command -v swift)" || { echo "error: swift not found in PATH or Xcode" >&2; exit 1; }
fi

APP_NAME="Git Plus"
EXECUTABLE="GitPlus"
BUNDLE_ID="co.egohub.gitplus"
VERSION="0.4.0"
OUT="build/${APP_NAME}.app"

echo "==> swift build -c release"
"$SWIFT" build -c release --product "$EXECUTABLE"
BIN="$("$SWIFT" build -c release --show-bin-path)/${EXECUTABLE}"

echo "==> assembling ${OUT}"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/${EXECUTABLE}"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${EXECUTABLE}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Git Plus</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Folder</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSItemContentTypes</key><array><string>public.folder</string></array>
            <key>LSHandlerRank</key><string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Sign with the stable local identity if present (run tools/setup-signing-cert.sh once).
# A fixed cert keeps the designated requirement constant across rebuilds, so macOS privacy
# grants (e.g. access to repositories in ~/Desktop or ~/Documents) survive every rebuild.
SIGN_HASH="$(security find-identity "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
    | awk '/Git Plus Local Signing/ {print $2; exit}')"
if [ -n "$SIGN_HASH" ]; then
    echo "==> signing with stable identity ($SIGN_HASH)"
    codesign --force --sign "$SIGN_HASH" --timestamp=none "$OUT" >/dev/null 2>&1
else
    echo "==> ad-hoc signing (run tools/setup-signing-cert.sh for a stable signature)"
    codesign --force --sign - --timestamp=none "$OUT" >/dev/null 2>&1
fi

echo "==> done: $(cd "$(dirname "$OUT")" && pwd)/${APP_NAME}.app"

if [ "${1:-}" = "--install" ]; then
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$OUT" /Applications/
    echo "==> installed: /Applications/${APP_NAME}.app"
fi
