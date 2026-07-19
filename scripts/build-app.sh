#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TokenViewer"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT/.build/AppIcon.iconset"
APP_ICON_SOURCE_DIR="$ROOT/App/Assets.xcassets/AppIcon.appiconset"

cd "$ROOT"
swift build -c release

rm -rf "$APP_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"
cp "$ROOT/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

cp "$APP_ICON_SOURCE_DIR/appicon-16.png" "$ICONSET_DIR/icon_16x16.png"
cp "$APP_ICON_SOURCE_DIR/appicon-32.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$APP_ICON_SOURCE_DIR/appicon-32.png" "$ICONSET_DIR/icon_32x32.png"
cp "$APP_ICON_SOURCE_DIR/appicon-64.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$APP_ICON_SOURCE_DIR/appicon-128.png" "$ICONSET_DIR/icon_128x128.png"
cp "$APP_ICON_SOURCE_DIR/appicon-256.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$APP_ICON_SOURCE_DIR/appicon-256.png" "$ICONSET_DIR/icon_256x256.png"
cp "$APP_ICON_SOURCE_DIR/appicon-512.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$APP_ICON_SOURCE_DIR/appicon-512.png" "$ICONSET_DIR/icon_512x512.png"
cp "$APP_ICON_SOURCE_DIR/appicon-1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>TokenViewer</string>
    <key>CFBundleExecutable</key>
    <string>TokenViewer</string>
    <key>CFBundleIdentifier</key>
    <string>com.qianchen.tokenviewer</string>
    <key>CFBundleName</key>
    <string>TokenViewer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"
echo "Built $APP_DIR"
