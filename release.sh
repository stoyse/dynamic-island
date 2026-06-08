#!/bin/bash
# Package a signed+notarized DMG and publish it as a GitHub release.
# Usage: ./release.sh            (uses CFBundleShortVersionString from Info.plist)
#        ./release.sh 1.1.0      (override the version/tag)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DynamicIsland"
APP="build/$APP_NAME.app"

# 1) Build + sign + notarize the DMG.
./package.sh

# 2) Resolve version / tag / artifact.
#    The tag may be overridden by the first arg; the DMG is always whatever
#    package.sh actually produced (avoids version-name mismatches).
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
TAG="v${1:-$VERSION}"
DMG="$(ls -t dist/*.dmg 2>/dev/null | head -1)"
[ -n "$DMG" ] && [ -f "$DMG" ] || { echo "✗ Kein DMG in dist/ gefunden"; exit 1; }
echo "› Release $TAG mit Artefakt: $DMG"

# 3) Tag the current commit.
git tag -f "$TAG"
git push -f origin "$TAG"

# 4) Release notes.
NOTES="$(mktemp)"
cat > "$NOTES" <<EOF
## Dynamic Island for macOS — $TAG

A Dynamic Island around your MacBook's notch: live music with an interactive
dotted-waveform scrubber, and your real-time Claude usage.

### Install
1. Download **$APP_NAME-$VERSION.dmg** below.
2. Open it and drag **Dynamic Island** into your **Applications** folder.
3. Launch it. On first run, allow **Automation** for Spotify / Google Chrome so
   playback controls and tap-to-open work.

The build is signed with a Developer ID and notarized by Apple, so it runs
without Gatekeeper warnings.

**Requirements:** macOS 13+ on a notched MacBook.
EOF

# 5) Create (or update) the GitHub release and upload the DMG.
if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG" --clobber
    gh release edit "$TAG" --notes-file "$NOTES" --title "Dynamic Island $TAG"
else
    gh release create "$TAG" "$DMG" --title "Dynamic Island $TAG" --notes-file "$NOTES"
fi

rm -f "$NOTES"
echo ""
echo "✓ Release veröffentlicht: $(gh repo view --json url -q .url)/releases/tag/$TAG"
