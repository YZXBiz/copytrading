#!/bin/sh
# Rebuilds resources/AppIcon.icns from resources/AppIcon.svg: rsvg-convert draws the 1024 px master, sips makes the other sizes, iconutil packs them.
set -e
cd "$(dirname "$0")/../resources"
set_dir=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set_dir"
rsvg-convert -w 1024 -h 1024 AppIcon.svg -o "$set_dir/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$set_dir/icon_512x512@2x.png" --out "$set_dir/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$set_dir/icon_512x512@2x.png" --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o AppIcon.icns
echo "$set_dir"
