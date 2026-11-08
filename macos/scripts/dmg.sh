#!/bin/zsh
# Package the existing release build. Finder writes the window layout into the image.
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/build/mica.app"
[[ -d "$app" ]] || { echo 'build/mica.app is missing; run scripts/build.sh release first' >&2; exit 1; }
codesign --verify --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$version" == [0-9]* && "$version" != *[^0-9.]* ]] || { echo 'invalid version' >&2; exit 1; }
output="$PWD/build/mica-$version.dmg"
work=$(mktemp -d "${TMPDIR:-/tmp}/mica-dmg.XXXXXXXX")
mount="$work/mount"
mkdir -p "$work/source/.background" "$mount"
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then hdiutil detach "$mount" -quiet || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
swift scripts/dmg-background.swift "$work/source/.background/background.png"
ditto "$app" "$work/source/mica.app"
ln -s /Applications "$work/source/Applications"
hdiutil create -quiet -volname "mica $version" -srcfolder "$work/source" -format UDRW -fs HFS+ "$work/staging.dmg"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$mount" "$work/staging.dmg"
mounted=1
osascript - "$mount" <<'APPLESCRIPT'
on run argv
    set volumePath to POSIX file (item 1 of argv) as alias
    tell application "Finder"
        open volumePath
        set w to container window of volumePath
        set current view of w to icon view
        set toolbar visible of w to false
        set statusbar visible of w to false
        set bounds of w to {200, 160, 920, 600}
        set viewOptions to icon view options of w
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png" of volumePath
        set position of item "mica.app" of volumePath to {170, 162}
        set position of item "Applications" of volumePath to {550, 162}
        update volumePath without registering applications
        delay 2
        close w
    end tell
end run
APPLESCRIPT
sync
hdiutil detach -quiet "$mount"
mounted=0
hdiutil convert -quiet "$work/staging.dmg" -format UDZO -imagekey zlib-level=9 -o "$work/final.dmg"
mv -f "$work/final.dmg" "$output"
(cd "${output:h}" && shasum -a 256 "${output:t}" > "${output:t}.sha256")
printf '%s\n' "$output" "$output.sha256"
