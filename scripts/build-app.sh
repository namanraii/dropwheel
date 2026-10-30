#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Dropwheel"
APP="$ROOT/dist/Dropwheel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dropwheel"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/Dropwheel"

if command -v magick >/dev/null 2>&1; then
  ICONSET="$ROOT/dist/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  magick -size 1024x1024 xc:none \
    -fill '#ff5200' -draw 'roundrectangle 64,64 960,960 220,220' \
    -stroke white -strokewidth 58 -fill none -draw 'circle 512,512 512,270' \
    -stroke none -fill white -draw 'circle 512,270 512,228' \
    "$ROOT/dist/icon-1024.png"
  for size in 16 32 128 256 512; do
    magick "$ROOT/dist/icon-1024.png" -resize ${size}x${size} "$ICONSET/icon_${size}x${size}.png"
    double=$((size * 2))
    magick "$ROOT/dist/icon-1024.png" -resize ${double}x${double} "$ICONSET/icon_${size}x${size}@2x.png"
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET" "$ROOT/dist/icon-1024.png"
fi

codesign --force --deep --sign - "$APP"
echo "$APP"
