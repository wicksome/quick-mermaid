#!/usr/bin/env bash
# QuickMermaid release: inject version → build dmg → (optional) upload GitHub Release.
#   ./release.sh 1.1.0            # inject version + build dmg (without publishing; shows next steps)
#   ./release.sh 1.1.0 --publish  # above + upload dmg via gh release create
set -euo pipefail
cd "$(dirname "$0")"

VER="${1:-}"
if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: ./release.sh <X.Y.Z> [--publish]" >&2
  exit 1
fi
TAG="v$VER"
PUBLISH=0
[[ "${2:-}" == "--publish" ]] && PUBLISH=1

echo "==> set version $VER in Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VER" Info.plist

echo "==> build dmg"
./build.sh --dmg

DMG="QuickMermaid-$VER.dmg"
mv -f build/QuickMermaid.dmg "$DMG"

echo "built: $PWD/$DMG"

if [[ "$PUBLISH" == "1" ]]; then
  echo "==> gh release create $TAG"
  gh release create "$TAG" "$DMG" \
    --repo wicksome/quick-mermaid \
    --title "$TAG" \
    --notes "QuickMermaid $VER" \
    --target main
  echo "released: https://github.com/wicksome/quick-mermaid/releases/tag/$TAG"
else
  echo
  echo "To publish:"
  echo "  1) ./release.sh $VER --publish   (or)"
  echo "     gh release create $TAG $DMG --repo wicksome/quick-mermaid --title \"$TAG\" --notes \"...\""
fi
