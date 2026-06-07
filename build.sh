#!/bin/bash
# Build DynamicIsland.app from the Swift sources (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DynamicIsland"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "› Cleaning…"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "› Compiling Swift sources…"
swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -framework AppKit -framework SwiftUI -framework Combine \
    -o "$MACOS_DIR/$APP_NAME" \
    Sources/*.swift

echo "› Assembling bundle…"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$RES_DIR/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist" >/dev/null

echo "› Ad-hoc code signing…"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (codesign skipped)"

echo "✓ Built $APP"
