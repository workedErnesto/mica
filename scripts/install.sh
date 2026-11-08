#!/bin/zsh
# Builds release, replaces /Applications/mica.app and refreshes the icon caches.
# A running mica is quit through its normal path first, so the session is written.
set -euo pipefail
cd "${0:A:h:h}"
swift test
scripts/build.sh release
if pgrep -f "/Applications/mica.app/Contents/MacOS/mica" >/dev/null; then
  was_running=1
  osascript -e 'tell application id "app.mica.browser" to quit'
  for i in {1..40}; do pgrep -f "/Applications/mica.app/Contents/MacOS/mica" >/dev/null || break; sleep 0.5; done
  if pgrep -f "/Applications/mica.app/Contents/MacOS/mica" >/dev/null; then echo "mica did not quit, install stopped" >&2; exit 1; fi
fi
rm -rf /Applications/mica.app
ditto build/mica.app /Applications/mica.app
codesign --verify --strict /Applications/mica.app
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u build/mica.app 2>/dev/null || true
"$lsregister" -f -R /Applications/mica.app
touch /Applications/mica.app
killall Dock
if [[ "${was_running:-0}" == 1 ]]; then open /Applications/mica.app; fi
echo "installed /Applications/mica.app"
