#!/bin/bash
# Build, Developer-ID–sign, package into a DMG, notarize and staple.
# Produces a download-ready, Gatekeeper-approved dist/DynamicIsland-<version>.dmg.
#
# Prerequisites (one-time, see README "Building a signed release"):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A stored notarytool keychain profile (default name: DynamicIsland), created with:
#        xcrun notarytool store-credentials "DynamicIsland" \
#          --apple-id "julian@vars-development.com" --team-id "NAL95468G3"
#
# Optional env overrides: SIGN_ID, NOTARY_PROFILE, SKIP_NOTARIZE=1
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DynamicIsland"
VOL_NAME="Dynamic Island"
APP="build/$APP_NAME.app"
ENTITLEMENTS="Resources/$APP_NAME.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-DynamicIsland}"
DIST="dist"

# 1) Fresh build (ad-hoc signed; we re-sign below with Developer ID).
./build.sh

# 2) Resolve the Developer ID Application signing identity.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [ -z "${SIGN_ID:-}" ]; then
    echo "✗ Kein 'Developer ID Application'-Zertifikat gefunden."
    echo "  Erstelle es einmalig in Xcode:"
    echo "    Settings → Accounts → <Team wählen> → Manage Certificates → + → Developer ID Application"
    echo "  (oder auf https://developer.apple.com/account/resources/certificates)"
    exit 1
fi
echo "› Signiere mit: $SIGN_ID"

# 3) Sign with Hardened Runtime + secure timestamp + entitlements.
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# 4) Determine version + output path.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p "$DIST"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

# 5) Build the styled DMG (custom dark background + drag-to-Applications).
echo "› Erzeuge gestyltes DMG…"
./dmg/make-dmg.sh "$APP" "$DMG" "$VOL_NAME" || true
if [ ! -f "$DMG" ]; then
    echo "› hdiutil-Fallback…"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    rm -rf "$STAGE"
fi

# 6) Sign the DMG itself.
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

# 7) Notarize + staple (unless skipped).
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "⚠︎ SKIP_NOTARIZE=1 — DMG ist signiert, aber NICHT notarisiert."
else
    echo "› Notarisiere (kann 1–5 Min dauern)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "› Hefte Notarisierungs-Ticket an (staple)…"
    xcrun stapler staple "$DMG"
fi

# 8) Verify Gatekeeper acceptance.
echo "› Verifiziere…"
spctl -a -t open --context context:primary-signing -v "$DMG" || true
echo ""
echo "✓ Fertig: $DMG"
ls -lh "$DMG" | awk '{print "  Größe:", $5}'
