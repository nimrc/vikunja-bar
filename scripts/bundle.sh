#!/bin/sh
# Builds dist/VikunjaBar.app (ad-hoc signed).
set -eu
cd "$(dirname "$0")/.."
swift build -c release
app=dist/VikunjaBar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/VikunjaBar" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "$app"
