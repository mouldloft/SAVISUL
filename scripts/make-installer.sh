#!/bin/zsh
# Builds dist/SAVISUL-<version>.dmg — the file to send to other people.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${SKIP_BUILD:-}" != 1 ]]; then
  zsh ./build.sh --no-install
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
APP="$PWD/dist/SAVISUL.app"
STAGE="$PWD/.build/dmg-root"
# Finder writes the path of this image into the DMG's window layout, so it is
# made outside the home folder, whose name is the builder's account name.
RW_DIR="$(mktemp -d /tmp/savisul-dmg.XXXXXX)"
RW="$RW_DIR/savisul-rw.dmg"
DMG="$PWD/dist/SAVISUL-$VERSION.dmg"
MOUNT="/Volumes/SAVISUL"
BACKGROUND="$PWD/.build/dmg-background.png"

swiftc -O -framework AppKit \
  -sdk "$PWD/.build/MacOSX.sdk" \
  -vfsoverlay "$PWD/.build/overlay.json" \
  -module-cache-path "$PWD/.build/module-cache" \
  -o "$PWD/.build/dmg-background" scripts/dmg_background.swift
"$PWD/.build/dmg-background" "$BACKGROUND"

rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/SAVISUL.app"
# The build keeps the SAVISUL certificate's signature. It is the same from release to release, so macOS keeps
# the permissions a person gave SAVISUL across updates, and the in-app updater accepts only builds that carry it.
# Gatekeeper never judges it: the install command and the updater both leave the quarantine check out.
codesign --verify --strict "$STAGE/SAVISUL.app"
if ! codesign -dr - "$STAGE/SAVISUL.app" 2>&1 | grep -q 'certificate root'; then
  echo "SAVISUL.app is not signed with the SAVISUL certificate; run scripts/signing.sh first." >&2
  exit 1
fi
# macOS 26 refuses a downloaded app and shows no "Open Anyway" button.
# The same steps pasted into Terminal are not checked by Gatekeeper.
cp scripts/open-savisul.zsh "$STAGE/Установить SAVISUL.command"
chmod +x "$STAGE/Установить SAVISUL.command"
{
  print -r -- "Если macOS пишет «Файл не был открыт», не удаляйте его."
  print -r -- "Откройте Терминал (Spotlight → Terminal), вставьте весь текст ниже и нажмите Enter."
  print -r -- "Образ SAVISUL (.dmg) должен лежать в папке «Загрузки»."
  print -r -- ""
  print -r -- "zsh <<'SAVISUL'"
  sed '1d' scripts/open-savisul.zsh
  print -r -- "SAVISUL"
} > "$STAGE/Если не открывается.txt"
cp "$BACKGROUND" "$STAGE/.background/background.png"
swiftc -O -framework AppKit -sdk "$PWD/.build/MacOSX.sdk" -vfsoverlay "$PWD/.build/overlay.json" \
  -module-cache-path "$PWD/.build/module-cache" -o "$PWD/.build/dmg-icons" scripts/dmg_icons.swift
"$PWD/.build/dmg-icons" "$STAGE/Установить SAVISUL.command" "$STAGE/Если не открывается.txt"
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

if [[ -d "$MOUNT" ]]; then
  hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
fi
rm -f "$RW" "$DMG"
hdiutil create -size 96m -fs HFS+ -volname "SAVISUL" -o "$RW" >/dev/null
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT" "$RW" >/dev/null

cp -R "$STAGE"/. "$MOUNT"/
chflags hidden "$MOUNT/.background" "$MOUNT/.VolumeIcon.icns"
# The helper files show without their extensions, so the row reads SAVISUL, Установить SAVISUL, Если не открывается.
/Library/Developer/CommandLineTools/usr/bin/SetFile -a E "$MOUNT/Установить SAVISUL.command"
/Library/Developer/CommandLineTools/usr/bin/SetFile -a E "$MOUNT/Если не открывается.txt"
/Library/Developer/CommandLineTools/usr/bin/SetFile -a C "$MOUNT"

osascript << EOF
tell application "Finder"
  tell disk "SAVISUL"
    open
    delay 1
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {200, 120, 920, 588}
    set theOptions to icon view options of theWindow
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 96
    set text size of theOptions to 12
    set background picture of theOptions to file ".background:background.png"
    set position of item "SAVISUL.app" of theWindow to {180, 206}
    set position of item "Установить SAVISUL.command" of theWindow to {360, 206}
    set position of item "Если не открывается.txt" of theWindow to {540, 206}
    update without registering applications
    delay 1
    close
    open
    delay 1
    update without registering applications
    delay 1
  end tell
end tell
EOF

rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes"
sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"
rmdir "$RW_DIR"

# A zip made this way keeps the executable bit. Packing the folder in Telegram does not,
# and macOS then reports that the app can't be opened.
ZIP="$PWD/dist/SAVISUL-$VERSION.zip"
PACK="$PWD/.build/savisul-pack"
rm -rf "$PACK" "$ZIP"
mkdir -p "$PACK"
ditto "$STAGE/SAVISUL.app" "$PACK/SAVISUL.app"
cp "$STAGE/Установить SAVISUL.command" "$PACK/Установить SAVISUL.command"
cp "$STAGE/Если не открывается.txt" "$PACK/Если не открывается.txt"
chmod +x "$PACK/Установить SAVISUL.command"
ditto -c -k --norsrc --keepParent "$PACK" "$ZIP"
rm -rf "$PACK"

cp "$STAGE/Если не открывается.txt" "$PWD/dist/Если не открывается.txt"
echo "Installer: $DMG"
echo "Zip: $ZIP"
echo "Steps: $PWD/dist/Если не открывается.txt"
du -h "$DMG" "$ZIP"
