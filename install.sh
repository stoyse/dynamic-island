#!/bin/bash
# Build, install to ~/Applications, and register a LaunchAgent so Dynamic Island
# always runs in the background and starts automatically at login.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DynamicIsland"
LABEL="com.julian.dynamicisland"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/$APP_NAME.app"
BIN="$DEST_APP/Contents/MacOS/$APP_NAME"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "› Building…"
./build.sh

echo "› Installing to $DEST_APP …"
mkdir -p "$DEST_DIR"
# Stop anything currently running so we can replace the bundle cleanly.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "$APP_NAME.app" 2>/dev/null || true
sleep 0.5
rm -rf "$DEST_APP"
cp -R "build/$APP_NAME.app" "$DEST_APP"

echo "› Writing LaunchAgent $PLIST …"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
PLISTEOF

echo "› Loading LaunchAgent…"
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true

sleep 1.5
if pgrep -f "$APP_NAME.app" >/dev/null; then
    echo "✓ Dynamic Island läuft und startet künftig automatisch beim Login."
else
    echo "⚠︎ Prozess nicht gefunden — prüfe: launchctl print gui/$(id -u)/$LABEL"
fi
