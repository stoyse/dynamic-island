#!/bin/bash
# Build a styled DMG (custom dark background + drag-to-Applications layout) from a .app.
# Usage: dmg/make-dmg.sh <app-path> <out.dmg> <volname>
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

APP="$1"; OUT="$2"; VOL="$3"
BG="dmg/background.png"
APP_BASENAME="$(basename "$APP")"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
mkdir "$STAGE/.background"; cp "$BG" "$STAGE/.background/background.png"
ln -s /Applications "$STAGE/Applications"

RW="$(mktemp -u).dmg"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null

hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | egrep '^/dev/' | head -1 | awk '{print $1}')"

# Finder styling. Errors are non-fatal — worst case the DMG ships without the
# custom background but still works.
osascript >/dev/null 2>&1 <<OSA || true
tell application "Finder"
  activate
  tell disk "$VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 540}
    set arrangement of the icon view options of container window to not arranged
    set icon size of the icon view options of container window to 110
    set background picture of the icon view options of container window to file ".background:background.png"
    set position of item "$APP_BASENAME" of container window to {175, 250}
    set position of item "Applications" of container window to {485, 250}
    update without registering applications
    delay 2
  end tell
end tell
OSA

sync
hdiutil detach "$DEV" -quiet 2>/dev/null || hdiutil detach "$DEV" -force -quiet 2>/dev/null || true
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$RW"; rm -rf "$STAGE"
echo "✓ styled DMG: $OUT"
