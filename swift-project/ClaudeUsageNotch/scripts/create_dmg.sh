#!/usr/bin/env bash
set -euo pipefail

# Create a DMG installer for ClaudeUsageNotch.
# Run ./scripts/build.sh first.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="ClaudeUsageNotch"
DMG_NAME="ClaudeUsageNotch-Installer"
BUILD_DIR="$PROJECT_DIR/build"
STAGING="$BUILD_DIR/dmg-staging"

if [ ! -d "$BUILD_DIR/$APP_NAME.app" ]; then
  echo "Missing $BUILD_DIR/$APP_NAME.app. Run ./scripts/build.sh first." >&2
  exit 1
fi

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$BUILD_DIR/$APP_NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$BUILD_DIR/$DMG_NAME.dmg"
hdiutil create \
  -volname "ClaudeUsageNotch" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$BUILD_DIR/$DMG_NAME.dmg"

echo "==> Created: $BUILD_DIR/$DMG_NAME.dmg"
echo ""
echo "Next: sign + notarize via ./scripts/sign_and_notarize.sh"
