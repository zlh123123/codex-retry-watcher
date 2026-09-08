#!/bin/bash
# Builds and installs /Applications/CodexRetryWatcher.app.
#
# It must live in /Applications because System Settings › Privacy & Security ›
# Accessibility browses with a Finder file picker, which will not show the
# hidden ~/.local directory.
#
# Override the destination with:  APP_DIR=/some/dir bash build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_DIR="${APP_DIR:-/Applications}"
APP="$APP_DIR/CodexRetryWatcher.app"
BIN="$APP/Contents/MacOS/CodexRetryWatcher"

if [[ ! -w "$APP_DIR" ]]; then
  echo "error: $APP_DIR is not writable by $(whoami)" >&2
  exit 1
fi

# Two copies of the same bundle confuse the Accessibility grant, which is keyed
# to the binary. Keep exactly one, in APP_DIR.
# A running instance would keep the old binary mapped while we replace the
# bundle, and its Accessibility grant is keyed to that binary.
pkill -f "CodexRetryWatcher.app/Contents/MacOS/CodexRetryWatcher" 2>/dev/null || true

rm -rf ./CodexRetryWatcher.app

# Build to a staging dir first so a failed compile cannot leave a half-installed
# app (and thus a silently dead LaunchAgent) behind.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/CodexRetryWatcher.app/Contents/MacOS"

cat > "$STAGE/CodexRetryWatcher.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CodexRetryWatcher</string>
  <key>CFBundleIdentifier</key><string>local.codex-retry-watcher</string>
  <key>CFBundleName</key><string>CodexRetryWatcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

swiftc -O AX.swift Watcher.swift MenuBar.swift main.swift -o "$STAGE/CodexRetryWatcher.app/Contents/MacOS/CodexRetryWatcher"

if [[ ! -f icon/AppIcon.icns ]]; then
  bash icon/make-icon.sh
fi
mkdir -p "$STAGE/CodexRetryWatcher.app/Contents/Resources"
cp icon/AppIcon.icns "$STAGE/CodexRetryWatcher.app/Contents/Resources/AppIcon.icns"

rm -rf "$APP"
mv "$STAGE/CodexRetryWatcher.app" "$APP"

# Sign in the final location. Without a stable signature macOS forgets the
# Accessibility grant on every rebuild.
codesign --force --sign - --identifier local.codex-retry-watcher "$APP"

# Let Launch Services notice the new bundle so it shows up in the picker.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
touch "$APP"

echo "installed: $APP"
echo "binary:    $BIN"
