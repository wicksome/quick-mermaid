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
# Assemble into build/ (gitignored) rather than the repo root, so the dev copy
# stays out of the way and is easy to discard (rm -rf build).
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/$APP"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
BIN=".build/$CONFIG/$APP_NAME"
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

echo "==> assembling $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/renderer.html "$APP_PATH/Contents/Resources/"
cp Resources/mermaid.min.js "$APP_PATH/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "built: $PWD/$APP_PATH"

for arg in "$@"; do
  case "$arg" in
    --selftest)
      echo "==> selftest"
      "$APP_PATH/Contents/MacOS/$APP_NAME" --selftest
      ;;
    --install)
      echo "==> install to /Applications + qmmd CLI"
      pkill -x QuickMermaid 2>/dev/null || true
      rm -rf /Applications/"$APP"
      cp -R "$APP_PATH" /Applications/
      xattr -dr com.apple.quarantine /Applications/"$APP" 2>/dev/null || true
      # install qmmd into a writable directory on PATH
      for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
        if [ -d "$d" ] && [ -w "$d" ]; then
          cp qmmd "$d/qmmd"; chmod +x "$d/qmmd"
          echo "   qmmd -> $d/qmmd"
          break
        fi
      done
      # The /Applications copy is canonical. Drop any Launch Services registration
      # of the build/ copy so it can't shadow it as a duplicate Services provider
      # (same bundle id → the right-click "Render Mermaid" item would go missing).
      "$LSREG" -u "$PWD/$APP_PATH" >/dev/null 2>&1 || true
      open /Applications/"$APP"
      echo "   installed & launched."
      ;;
    --dmg)
      echo "==> hdiutil create dmg"
      rm -f "$DMG_PATH"
      hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH" >/dev/null
      echo "built: $PWD/$DMG_PATH"
      ;;
  esac
done
