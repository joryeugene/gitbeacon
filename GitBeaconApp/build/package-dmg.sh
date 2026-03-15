#!/usr/bin/env bash
# package-dmg.sh: Create a distributable DMG with GitBeacon.app + Applications symlink.
# Usage: ./build/package-dmg.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${REPO_ROOT}/.build/GitBeacon.app"
DMG_DIR="${REPO_ROOT}/.build/dmg-staging"
DMG_OUT="${REPO_ROOT}/.build/GitBeacon.dmg"

[[ -d "$APP_DIR" ]] || { echo "GitBeacon.app not found. Run: ./build/package-app.sh release"; exit 1; }

echo "Creating GitBeacon.dmg..."

rm -rf "$DMG_DIR" "$DMG_OUT"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "GitBeacon" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_OUT"

rm -rf "$DMG_DIR"
echo "Built: $DMG_OUT"
