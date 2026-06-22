#!/usr/bin/env bash
# Build FlutterRunner.app and package it into a distributable DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

./build-app.sh

APP="FlutterRunner.app"
NAME="FlutterGUIRunner"
STAGE="$(mktemp -d)"
mkdir -p dist

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "dist/$NAME.dmg"
hdiutil create -volname "Flutter GUI Runner" \
  -srcfolder "$STAGE" -ov -format UDZO "dist/$NAME.dmg" >/dev/null
rm -rf "$STAGE"

echo "✅ dist/$NAME.dmg"
