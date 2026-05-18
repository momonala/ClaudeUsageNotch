#!/usr/bin/env bash
set -euo pipefail

# Sign and notarize Notchy Limit for distribution.
# Requires an Apple Developer ID and a configured notarytool keychain profile.
#
#   xcrun notarytool store-credentials "notchylimit-notarize" \
#       --apple-id "you@example.com" \
#       --team-id "YOURTEAMID" \
#       --password "app-specific-password"
#
# Env vars:
#   DEVELOPER_ID_APP      e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE        keychain profile name (default: notchylimit-notarize)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="NotchyLimit"
DMG_NAME="NotchyLimit-Installer"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-notchylimit-notarize}"

if [ -z "${DEVELOPER_ID_APP:-}" ]; then
  echo "DEVELOPER_ID_APP env var is required (e.g. 'Developer ID Application: Your Name (TEAMID)')." >&2
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo "Missing $APP_PATH. Run ./scripts/build.sh first." >&2
  exit 1
fi

echo "==> Codesigning .app (hardened runtime)"
codesign --force --deep --options runtime \
  --entitlements "$PROJECT_DIR/Sources/Resources/NotchyLimit.entitlements" \
  --sign "$DEVELOPER_ID_APP" \
  "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [ ! -f "$DMG_PATH" ]; then
  echo "==> DMG not found, building it"
  "$SCRIPT_DIR/create_dmg.sh"
fi

echo "==> Codesigning DMG"
codesign --force --sign "$DEVELOPER_ID_APP" "$DMG_PATH"

echo "==> Submitting to Apple notary service"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler staple "$APP_PATH"

echo "==> Done. Signed + notarized DMG: $DMG_PATH"
