#!/usr/bin/env bash
# Draws a 1024 PNG, converts it to an iconset, and generates AppIcon.icns in Resources.
set -euo pipefail
cd "$(dirname "$0")/.."

PNG="$(mktemp -t mqicon).png"
swift tools/make-icon.swift "$PNG"

SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
gen() { sips -z "$2" "$2" "$PNG" --out "$SET/icon_$1.png" >/dev/null; }
gen 16x16 16;      sips -z 32 32 "$PNG" --out "$SET/icon_16x16@2x.png" >/dev/null
gen 32x32 32;      sips -z 64 64 "$PNG" --out "$SET/icon_32x32@2x.png" >/dev/null
gen 128x128 128;   sips -z 256 256 "$PNG" --out "$SET/icon_128x128@2x.png" >/dev/null
gen 256x256 256;   sips -z 512 512 "$PNG" --out "$SET/icon_256x256@2x.png" >/dev/null
gen 512x512 512;   cp "$PNG" "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
