#!/bin/zsh
# Usage: ./build.sh [--no-install]
set -euo pipefail
cd "$(dirname "$0")"
INSTALL=1
[[ "${1:-}" == "--no-install" ]] && INSTALL=0
BUNDLE_ID="com.savisul.menu"
mkdir -p .build dist
SDK_SRC="/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk"
SDK=".build/MacOSX.sdk"
if [[ ! -f "$SDK/.savisul-patched" ]]; then
  rm -rf "$SDK"
  cp -R "$SDK_SRC" "$SDK"
  find "$SDK" -name '*.swiftinterface' -print0 \
    | xargs -0 sed -i '' 's/swiftlang-6.0.3.1.5/swiftlang-6.0.3.1.10/g'
  touch "$SDK/.savisul-patched"
fi
cat > .build/empty.modulemap << 'EOF'
// module.modulemap already defines SwiftBridging.
EOF
cat > .build/overlay.json << EOF
{
  "version": 0,
  "roots": [
    {
      "type": "directory",
      "name": "/Library/Developer/CommandLineTools/usr/include/swift",
      "contents": [
        {
          "type": "file",
          "name": "bridging.modulemap",
          "external-contents": "$PWD/.build/empty.modulemap"
        }
      ]
    }
  ]
}
EOF
SYS_SDK="$(xcrun --show-sdk-path)"
clang -c Sources/SMCBridge/smc_bridge.c \
  -I Sources/SMCBridge/include \
  -isysroot "$SYS_SDK" \
  -mmacosx-version-min=14.2 \
  -O2 \
  -o .build/smc_bridge.o
swiftc -parse-as-library \
  -target arm64-apple-macos14.2 \
  -sdk "$PWD/$SDK" \
  -vfsoverlay "$PWD/.build/overlay.json" \
  -module-cache-path "$PWD/.build/module-cache" \
  -O \
  -I Sources/SMCBridge/include \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework IOKit \
  -framework UserNotifications \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -framework CoreGraphics \
  -framework Carbon \
  -framework QuickLookThumbnailing \
  -framework UniformTypeIdentifiers \
  -framework EventKit \
  -framework AVFoundation \
  -framework ScreenCaptureKit \
  -framework Accelerate \
  -framework CoreMedia \
  -framework CoreMediaIO \
  Sources/SAVISUL/**/*.swift \
  .build/smc_bridge.o \
  -o .build/SAVISUL

# Now Playing runs in /usr/bin/perl, the one process MediaRemote still answers, through this library.
clang -fobjc-arc -O2 -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=14.2 \
  -isysroot "$SYS_SDK" -framework Foundation \
  -install_name @rpath/libSAVISULMedia.dylib \
  -o .build/libSAVISULMedia.dylib \
  Sources/MediaBridge/media_bridge.m

# Fan control runs as a small root daemon the user installs once; it ships inside the app.
clang -O2 -Wall -Wextra -arch arm64 -arch x86_64 -mmacosx-version-min=14.2 \
  -isysroot "$SYS_SDK" -framework IOKit -framework CoreFoundation \
  -o .build/savisul-fan-helper \
  Sources/FanHelper/fan_helper.c

APP="dist/SAVISUL.app"
rm -rf "$APP" .build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/SAVISUL "$APP/Contents/MacOS/SAVISUL"
cp .build/libSAVISULMedia.dylib "$APP/Contents/Frameworks/libSAVISULMedia.dylib"
cp .build/savisul-fan-helper "$APP/Contents/Resources/savisul-fan-helper"
chmod 755 "$APP/Contents/Resources/savisul-fan-helper"
cp Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/SAVISUL"
.build/SAVISUL --render-icon .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# The browser extension ships inside the app; on launch SAVISUL copies it to Application Support
# and registers itself as the extension's native messaging host.
mkdir -p Extension/icons
.build/SAVISUL --render-extension-icons Extension/icons
ditto --norsrc --noextattr Extension "$APP/Contents/Resources/Extension"
find "$APP/Contents/Resources/Extension" -name '.DS_Store' -delete
xattr -cr "$APP"

# Privacy grants follow the designated requirement, so a stable certificate keeps them across rebuilds.
SIGNED="ad-hoc"
MEDIA="$APP/Contents/Frameworks/libSAVISULMedia.dylib"
FANS="$APP/Contents/Resources/savisul-fan-helper"
if KC="$(zsh scripts/signing.sh 2>/dev/null)" &&
   codesign --force --timestamp=none --keychain "$KC" --sign "SAVISUL Local Signing" "$MEDIA" 2>/dev/null &&
   codesign --force --timestamp=none --keychain "$KC" --sign "SAVISUL Local Signing" --identifier com.savisul.fanhelper "$FANS" 2>/dev/null &&
   codesign --force --timestamp=none --keychain "$KC" --sign "SAVISUL Local Signing" --identifier "$BUNDLE_ID" "$APP" 2>/dev/null; then
  SIGNED="SAVISUL Local Signing"
else
  codesign --force --sign - "$MEDIA"
  codesign --force --sign - --identifier com.savisul.fanhelper "$FANS"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP (signed: $SIGNED)"

# Entries granted to earlier ad-hoc builds never match the new signature; clear them once.
if [[ "$SIGNED" != "ad-hoc" && -f .signing/fresh-identity ]]; then
  for service in Accessibility ScreenCapture ListenEvent PostEvent; do
    tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
  done
  defaults delete "$BUNDLE_ID" axRequested >/dev/null 2>&1 || true
  defaults delete "$BUNDLE_ID" screenRequested >/dev/null 2>&1 || true
  rm -f .signing/fresh-identity
  echo "Reset privacy entries left by ad-hoc builds"
fi

(( INSTALL )) || exit 0
DEST="/Applications/SAVISUL.app"
[[ -w /Applications ]] || { mkdir -p "$HOME/Applications"; DEST="$HOME/Applications/SAVISUL.app"; }
if pgrep -x SAVISUL >/dev/null 2>&1; then
  pkill -TERM -x SAVISUL || true
  for _ in {1..50}; do
    pgrep -x SAVISUL >/dev/null 2>&1 || break
    sleep 0.1
  done
  pkill -KILL -x SAVISUL >/dev/null 2>&1 || true
fi
rm -rf "$DEST"
ditto "$APP" "$DEST"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
open "$DEST"
echo "Installed and opened $DEST"
