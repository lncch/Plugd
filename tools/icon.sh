#!/bin/bash
# Renders brand/plugd-icon.svg (from Claude Design) into AppIcon.icns and docs/img/icon.png.
# Uses headless Chrome because ImageMagick's SVG reader drops the drop-shadow filter.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
printf '<html><body style="margin:0"><img src="file://%s/brand/plugd-icon.svg" width="1024" height="1024" style="display:block"></body></html>' "$PWD" > "$T/i.html"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --default-background-color=00000000 --window-size=1024,1024 \
  --user-data-dir="$T/prof" --screenshot="$T/1024.png" "file://$T/i.html" >/dev/null 2>&1 &
CP=$!
for _ in $(seq 1 30); do [ -s "$T/1024.png" ] && break; sleep 1; done
sleep 1; kill $CP 2>/dev/null || true  # headless Chrome does not always exit on its own
mkdir -p "$T/AppIcon.iconset"
for n in 16 32 128 256 512; do
  magick "$T/1024.png" -resize ${n}x${n} "$T/AppIcon.iconset/icon_${n}x${n}.png"
  magick "$T/1024.png" -resize $((n*2))x$((n*2)) "$T/AppIcon.iconset/icon_${n}x${n}@2x.png"
done
iconutil -c icns "$T/AppIcon.iconset" -o AppIcon.icns
magick "$T/1024.png" -resize 256x256 docs/img/icon.png
cp "$T/1024.png" brand/plugd-icon-1024.png
rm -rf "$T"
echo "wrote AppIcon.icns docs/img/icon.png brand/plugd-icon-1024.png"
