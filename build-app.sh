#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
OUTPUT_DIR="$ROOT_DIR/outputs"
WORK_DIR="$ROOT_DIR/work/build"
APP_DIR="$OUTPUT_DIR/ShotKey.app"

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/ShotKey" "$APP_DIR/Contents/MacOS/ShotKey"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

swiftc "Tools/IconMaker.swift" -o "$WORK_DIR/icon-maker"
ICONSET="$WORK_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
"$WORK_DIR/icon-maker" "$WORK_DIR/icon-1024.png"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" "512:512x512" "1024:512x512@2x"; do
  pixels="${spec%%:*}"
  name="${spec#*:}"
  sips -z "$pixels" "$pixels" "$WORK_DIR/icon-1024.png" --out "$ICONSET/icon_${name}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
