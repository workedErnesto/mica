#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
swift build -c "$configuration"
app_path="$PWD/build/mica.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp ".build/$configuration/mica" "$app_path/Contents/MacOS/mica"
cp Resources/Blocklist/blocklist.txt Resources/Blocklist/BLOCKLIST-NOTICE.txt "$app_path/Contents/Resources/"
cp Resources/App/Info.plist "$app_path/Contents/Info.plist"
for lang in en ru; do mkdir -p "$app_path/Contents/Resources/$lang.lproj"; cp "Resources/App/$lang.lproj/InfoPlist.strings" "$app_path/Contents/Resources/$lang.lproj/"; done
if [[ -f Resources/App/mica.icns ]]; then cp Resources/App/mica.icns "$app_path/Contents/Resources/"; fi
rm -rf "$app_path/Contents/Resources/AppIcons"
if [[ -d Resources/AppIcons ]]; then mkdir -p "$app_path/Contents/Resources/AppIcons"; cp Resources/AppIcons/*.heic Resources/AppIcons/NOTICE.txt "$app_path/Contents/Resources/AppIcons/"; fi
plugin="$app_path/Contents/PlugIns/MicaDockTile.docktileplugin"
rm -rf "$app_path/Contents/PlugIns"
mkdir -p "$plugin/Contents/MacOS"
cp Sources/MicaDockTile/Info.plist "$plugin/Contents/Info.plist"
optimization=$([[ "$configuration" == "release" ]] && echo -O || echo -Onone)
swiftc $optimization -parse-as-library -module-name MicaDockTile -target "$(uname -m)-apple-macos15.4" -emit-executable -Xlinker -bundle Sources/MicaDockTile/MicaDockTile.swift -o "$plugin/Contents/MacOS/MicaDockTile"
codesign --force --sign - "$plugin"
rm -rf "$app_path/Contents/Resources/QA"
entitlements="Resources/App/mica.entitlements"
if [[ "$configuration" == "debug" ]]; then
  mkdir -p "$app_path/Contents/Resources/QA"
  cp -R Tests/Fixtures/extension-check "$app_path/Contents/Resources/QA/"
  cp "$entitlements" build/debug.entitlements
  /usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool true' build/debug.entitlements
  entitlements="build/debug.entitlements"
fi
codesign --force --sign - --entitlements "$entitlements" "$app_path"
codesign --verify --strict "$app_path"
printf '%s\n' "$app_path"
