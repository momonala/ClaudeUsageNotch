#!/usr/bin/env bash
set -euo pipefail

# Build script for ClaudeUsageNotch.
# Mode A (default): swiftc — no Xcode required, works with CLI tools only.
# Mode B: xcodebuild — set USE_XCODEBUILD=1 if Xcode is installed.
#   Requires: Xcode 15+ and `brew install xcodegen` for Mode B.

BLUE='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}==> $*${NC}"; }
log_ok()   { echo -e "${GREEN}==> $*${NC}"; }
log_warn() { echo -e "${YELLOW}==> $*${NC}"; }
log_err()  { echo -e "${RED}==> $*${NC}" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="ClaudeUsageNotch"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
SOURCES_DIR="$PROJECT_DIR/Sources"
ASSETS_DIR="$SOURCES_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
SDK=$(xcrun --show-sdk-path --sdk macosx)

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [[ -n "$SIGN_IDENTITY" ]]; then
  SIGN_DESC="signed: $SIGN_IDENTITY"
else
  SIGN_DESC="ad-hoc signed — local use only"
fi

# Set a plist key, adding it if it doesn't already exist in the template.
plist_set_or_add() {
  local key="$1" value="$2" type="${3:-string}"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$APP_CONTENTS/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$APP_CONTENTS/Info.plist"
}

# Build AppIcon.icns from the PNG set. Best-effort: a missing icon shouldn't fail the build.
build_icns() {
  # iconutil requires the directory name to end in ".iconset" exactly, so
  # mktemp's random suffix (appended after the template) can't be used here.
  local iconset_parent iconset spec px name
  iconset_parent=$(mktemp -d)
  iconset="$iconset_parent/$APP_NAME.iconset"
  mkdir -p "$iconset"

  # px:target-name — each source PNG (AppIcon-<px>.png) is reused for both its
  # native slot and the next size down's @2x slot.
  for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
              128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 \
              512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "$px" "$px" "$ASSETS_DIR/AppIcon-${px}.png" --out "$iconset/${name}.png" >/dev/null
  done

  iconutil -c icns "$iconset" -o "$APP_CONTENTS/Resources/AppIcon.icns" 2>/dev/null \
    || log_warn "AppIcon.icns generation skipped — dock icon may be missing"
  rm -rf "$iconset_parent"
}

# Sign the bundle with SIGN_IDENTITY, or ad-hoc so macOS will still launch it locally.
sign_bundle() {
  xattr -cr "$APP_BUNDLE" 2>/dev/null || true
  if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE" \
      && codesign --verify --strict "$APP_BUNDLE" \
      || { log_err "Signing failed — check that the cert is valid in Keychain."; exit 1; }
  else
    codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
  fi
}

# Assemble the .icns, copy brand assets, and sign. Shared by both build modes
# so a Mode B (xcodebuild) app gets the same notch-specific treatment as Mode A.
finalize_bundle() {
  cp "$SOURCES_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.claudeusagenotch.ClaudeUsageNotch" "$APP_CONTENTS/Info.plist"
  plist_set_or_add CFBundleIconFile AppIcon

  if [ -f "$SOURCES_DIR/Resources/BrandIcons/brand-claude.png" ]; then
    cp "$SOURCES_DIR/Resources/BrandIcons/brand-claude.png" "$APP_CONTENTS/Resources/"
  fi

  build_icns
  sign_bundle
}

rm -rf "$BUILD_DIR"
mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources"

# ── Mode B: xcodebuild ──────────────────────────────────────────────────────
if [[ "${USE_XCODEBUILD:-0}" == "1" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    log_err "xcodegen not found. Install with: brew install xcodegen"
    exit 1
  fi
  DERIVED_DATA="$PROJECT_DIR/.derived-data"
  CONFIGURATION="${CONFIGURATION:-Release}"
  log_info "Building $APP_NAME ($CONFIGURATION) via xcodebuild"
  xcodegen generate
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
  [ -d "$APP_BUILT_PATH" ] || { log_err "Build failed: $APP_BUILT_PATH not found"; exit 1; }
  cp -R "$APP_BUILT_PATH" "$BUILD_DIR/"
  finalize_bundle

  log_ok "Built ($SIGN_DESC): $APP_BUNDLE"
  echo "    open $APP_BUNDLE"
  exit 0
fi

# ── Mode A: swiftc (no Xcode required) ─────────────────────────────────────
log_info "Building $APP_NAME (swiftc)"

SWIFT_SOURCES=()
while IFS= read -r f; do SWIFT_SOURCES+=("$f"); done < <(find "$SOURCES_DIR" -name "*.swift" | sort)

swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx26.0 \
  -O \
  -module-name "$APP_NAME" \
  -o "$APP_CONTENTS/MacOS/$APP_NAME" \
  "${SWIFT_SOURCES[@]}" \
  || { log_err "Compilation failed."; exit 1; }

finalize_bundle

log_ok "Built ($SIGN_DESC): $APP_BUNDLE"
echo "    open $APP_BUNDLE"
