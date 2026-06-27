#!/usr/bin/env bash
# QuickMermaid build script — creates .app / .dmg via CLI without the Xcode IDE.
#   ./build.sh           # build .app only
#   ./build.sh --dmg     # build .app + .dmg
#   ./build.sh --selftest# build then run the render pipeline self-test
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="QuickMermaid"
CONFIG="release"
APP="$APP_NAME.app"
BIN=".build/$CONFIG/$APP_NAME"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/renderer.html "$APP/Contents/Resources/"
cp Resources/mermaid.min.js "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "built: $PWD/$APP"

for arg in "$@"; do
  case "$arg" in
    --selftest)
      echo "==> selftest"
      "$APP/Contents/MacOS/$APP_NAME" --selftest
      ;;
    --install)
      echo "==> install to /Applications + qmmd CLI"
      pkill -x QuickMermaid 2>/dev/null || true
      rm -rf /Applications/"$APP"
      cp -R "$APP" /Applications/
      xattr -dr com.apple.quarantine /Applications/"$APP" 2>/dev/null || true
      # install qmmd into a writable directory on PATH
      for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
        if [ -d "$d" ] && [ -w "$d" ]; then
          cp qmmd "$d/qmmd"; chmod +x "$d/qmmd"
          echo "   qmmd -> $d/qmmd"
          break
        fi
      done
      open /Applications/"$APP"
      echo "   installed & launched."
      ;;
    --dmg)
      echo "==> hdiutil create dmg"
      rm -f "$APP_NAME.dmg"
      hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$APP_NAME.dmg" >/dev/null
      echo "built: $PWD/$APP_NAME.dmg"
      ;;
  esac
done
