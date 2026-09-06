#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
OUTPUT_DIR="$ROOT_DIR/outputs"
STAGE_DIR="$ROOT_DIR/work/dmg-stage"
DMG_PATH="$OUTPUT_DIR/ShotKey-1.2.dmg"

"$ROOT_DIR/build-app.sh"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$OUTPUT_DIR/ShotKey.app" "$STAGE_DIR/ShotKey.app"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "ShotKey 1.2" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
echo "$DMG_PATH"
