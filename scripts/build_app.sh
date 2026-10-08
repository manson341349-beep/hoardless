#!/bin/bash
# Builds build/Hoardless.app for local use (ad-hoc signed, not notarized).
# Usage: scripts/build_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Hoardless
BIN="$(swift build -c release --show-bin-path)"
APP="build/Hoardless.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Hoardless" "$APP/Contents/MacOS/Hoardless"
cp -R rules/apps "$APP/Contents/Resources/rules"
cp -R Sources/Hoardless/Resources/Art "$APP/Contents/Resources/Art"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Hoardless</string>
    <key>CFBundleDisplayName</key><string>Hoardless</string>
    <key>CFBundleIdentifier</key><string>io.github.manson341349-beep.hoardless</string>
    <key>CFBundleExecutable</key><string>Hoardless</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
