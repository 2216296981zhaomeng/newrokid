#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$PLUGIN_DIR/dist"
STAGE_DIR="$PLUGIN_DIR/build/ios-nativeplugin"
OUT_ZIP="$DIST_DIR/Rokid-Glass-ios-nativeplugin.zip"

rm -rf "$STAGE_DIR" "$OUT_ZIP"
mkdir -p "$STAGE_DIR/Rokid-Glass" "$DIST_DIR"

rsync -a --delete \
  --exclude "build" \
  --exclude "dist" \
  "$PLUGIN_DIR/package.json" \
  "$STAGE_DIR/Rokid-Glass/package.json"

rsync -a --delete \
  --exclude ".DS_Store" \
  "$PLUGIN_DIR/ios/" \
  "$STAGE_DIR/Rokid-Glass/ios/"

cd "$STAGE_DIR"
/usr/bin/zip -qry "$OUT_ZIP" "Rokid-Glass"

echo "Packaged $OUT_ZIP"
