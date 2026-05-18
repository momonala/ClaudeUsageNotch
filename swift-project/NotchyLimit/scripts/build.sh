#!/usr/bin/env bash
set -euo pipefail

# Build script for Notchy Limit.
# Requires: Xcode 15+, XcodeGen (brew install xcodegen).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="$PROJECT_DIR/.derived-data"
APP_NAME="NotchyLimit"
CONFIGURATION="${CONFIGURATION:-Release}"

echo "==> Generating Xcode project (XcodeGen)"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate

echo "==> Cleaning previous build artifacts"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building $APP_NAME ($CONFIGURATION)"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_BUILT_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [ ! -d "$APP_BUILT_PATH" ]; then
  echo "Build failed: $APP_BUILT_PATH not found" >&2
  exit 1
fi

cp -R "$APP_BUILT_PATH" "$BUILD_DIR/"
echo "==> Built: $BUILD_DIR/$APP_NAME.app"
echo ""
echo "Run with: open $BUILD_DIR/$APP_NAME.app"
