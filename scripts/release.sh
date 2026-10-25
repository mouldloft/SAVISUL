#!/bin/zsh
# Builds what savisul.com hands out, from the current sources: dist/SAVISUL-<version>.dmg and .zip, signed with the
# Developer ID of Mould Loft's Apple team, notarized by Apple and stapled, so a downloaded copy opens at once: no
# warning, no Terminal, no trip to System Settings. The zip is the in-app update as well: SAVISUL from savisul.com takes
# only builds signed this way. The open-source build is GitHub's, signed with the SAVISUL certificate.
#
# Needs, once, on the Mac that releases (by whoever owns the Apple Developer account; no secret passes through here):
#   1. Xcode → Settings → Accounts → the team → Manage Certificates… → + → Developer ID Application.
#   2. xcrun notarytool store-credentials savisul-notary --apple-id <Apple ID> --team-id QR26Z476AT
#      It asks for an app-specific password (made at account.apple.com → Sign-In and Security) and keeps it in the
#      login keychain.
# Test the steps without either: SIGN_IDENTITY=- signs ad hoc and leaves notarization out.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/notarize.zsh

TEAM=QR26Z476AT
export NOTARY_PROFILE="${NOTARY_PROFILE:-savisul-notary}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .* ($TEAM)\)\".*/\1/p" | head -1)}"
if [[ -z "$IDENTITY" ]]; then
  print -u2 "No “Developer ID Application” certificate of team $TEAM in the keychain: see step 1 at the top of this script."
  exit 1
fi
DRY=$([[ "$IDENTITY" == "-" ]] && print 1 || print "")
if [[ -z "$DRY" ]] && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  print -u2 "No notarization profile “$NOTARY_PROFILE” in the keychain: see step 2 at the top of this script."
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
zsh ./build.sh --no-install
WORK="$PWD/.build/release"
rm -rf "$WORK"
mkdir -p "$WORK"

# Signed again, from the inside out, under the hardened runtime with a secure timestamp.
APP="$WORK/SAVISUL.app"
ditto dist/SAVISUL.app "$APP"
sign() {
  if [[ -n "$DRY" ]]; then codesign --force --options runtime --sign - "$@"
  else codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; fi
}
sign "$APP/Contents/Frameworks/libSAVISULMedia.dylib"
sign --identifier com.savisul.fanhelper "$APP/Contents/Resources/savisul-fan-helper"
sign --identifier com.savisul.menu --entitlements SAVISUL.entitlements "$APP"
codesign --verify --strict --deep "$APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q 'com.apple.security.device.camera' || { print -u2 "The entitlements didn't take."; exit 1; }

if [[ -z "$DRY" ]]; then
  # Apple's notary service checks it; its ticket is then stapled to the app, so it opens offline as well.
  ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
  notarize "$WORK/notarize.zip"
  xcrun stapler staple "$APP"
  # What Gatekeeper will say to someone who downloaded it.
  spctl --assess --type execute -vv "$APP"
fi

# The disk image and the zip on savisul.com, both from the notarized app.
SKIP_BUILD=1 APP_SOURCE="$APP" SIGN_IDENTITY="$IDENTITY" zsh scripts/make-installer.sh

print "Release $VERSION: dist/SAVISUL-$VERSION.dmg, and dist/SAVISUL-$VERSION.zip for the download and the in-app update"
print "  (Developer ID${DRY:+; DRY RUN: ad hoc, not notarized})"
