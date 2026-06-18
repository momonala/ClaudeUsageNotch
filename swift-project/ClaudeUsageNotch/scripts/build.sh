#!/usr/bin/env bash
set -euo pipefail

# Build script for ClaudeUsageNotch.
# Mode A (default): swiftc — no Xcode required, works with CLI tools only.
# Mode B: xcodebuild — set USE_XCODEBUILD=1 if Xcode is installed.
#   Requires: Xcode 15+ and `brew install xcodegen` for Mode B.

# ANSI colors
BLUE='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

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

echo -e "${BLUE}==> Cleaning previous build artifacts${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources"

# ── Mode B: xcodebuild ──────────────────────────────────────────────────────
if [[ "${USE_XCODEBUILD:-0}" == "1" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install with: brew install xcodegen" >&2; exit 1
  fi
  DERIVED_DATA="$PROJECT_DIR/.derived-data"
  CONFIGURATION="${CONFIGURATION:-Release}"
  echo -e "${BLUE}==> Generating Xcode project (XcodeGen)${NC}"
  xcodegen generate
  echo -e "${BLUE}==> Building $APP_NAME ($CONFIGURATION) via xcodebuild${NC}"
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
    echo "Build failed: $APP_BUILT_PATH not found" >&2; exit 1
  fi
  cp -R "$APP_BUILT_PATH" "$BUILD_DIR/"
  echo -e "${GREEN}==> Built (xcodebuild): $BUILD_DIR/$APP_NAME.app${NC}"
  echo -e "${YELLOW}Run with: open $BUILD_DIR/$APP_NAME.app${NC}"
  exit 0
fi

# ── Mode A: swiftc (no Xcode required) ─────────────────────────────────────
echo ""
echo "  NOTE: Mode A produces an UNSIGNED binary for local use only."
echo "  Do not distribute this build. For a distributable binary, use"
echo "  Mode B (USE_XCODEBUILD=1) with a Developer ID and scripts/sign_and_notarize.sh."
echo ""
echo -e "${BLUE}==> Compiling $APP_NAME with swiftc (no Xcode required)${NC}"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx26.0 \
  -O \
  -module-name "$APP_NAME" \
  -o "$APP_CONTENTS/MacOS/$APP_NAME" \
  "$SOURCES_DIR/App/ClaudeUsageNotchApp.swift" \
  "$SOURCES_DIR/App/AppDelegate.swift" \
  "$SOURCES_DIR/Core/Domain/Status.swift" \
  "$SOURCES_DIR/Core/Domain/UsageWindow.swift" \
  "$SOURCES_DIR/Core/Domain/ServiceUsageSnapshot.swift" \
  "$SOURCES_DIR/Core/Domain/UsageRecord.swift" \
  "$SOURCES_DIR/Core/Domain/QuotaSnapshotPayload.swift" \
  "$SOURCES_DIR/Core/Domain/AnalyticsData.swift" \
  "$SOURCES_DIR/Core/State/AppSettings.swift" \
  "$SOURCES_DIR/Core/State/AppState.swift" \
  "$SOURCES_DIR/Core/State/NotchState.swift" \
  "$SOURCES_DIR/Platform/KeychainStore.swift" \
  "$SOURCES_DIR/Platform/ScreenUtils.swift" \
  "$SOURCES_DIR/Providers/Claude/ClaudeCredential.swift" \
  "$SOURCES_DIR/Providers/Claude/ClaudeEndpoint.swift" \
  "$SOURCES_DIR/Providers/Claude/ClaudeUsageDTO.swift" \
  "$SOURCES_DIR/Providers/Claude/ClaudeOAuthCredential.swift" \
  "$SOURCES_DIR/Providers/Claude/ClaudeProvider.swift" \
  "$SOURCES_DIR/Services/AuthService.swift" \
  "$SOURCES_DIR/Services/IncidentMonitor.swift" \
  "$SOURCES_DIR/Services/NotificationService.swift" \
  "$SOURCES_DIR/Services/UsageCoordinator.swift" \
  "$SOURCES_DIR/Services/QuotaSyncService.swift" \
  "$SOURCES_DIR/Services/UsageService.swift" \
  "$SOURCES_DIR/Services/LocalHistoryReader.swift" \
  "$SOURCES_DIR/Services/RemoteHistoryReader.swift" \
  "$SOURCES_DIR/Services/HistorySyncService.swift" \
  "$SOURCES_DIR/UI/Theme/Theme.swift" \
  "$SOURCES_DIR/UI/Theme/BrandIcon.swift" \
  "$SOURCES_DIR/UI/Theme/GlassBackground.swift" \
  "$SOURCES_DIR/UI/Theme/RetroMascot.swift" \
  "$SOURCES_DIR/UI/Compact/StatusDot.swift" \
  "$SOURCES_DIR/UI/Compact/CompactProgressBar.swift" \
  "$SOURCES_DIR/UI/Compact/CompactView.swift" \
  "$SOURCES_DIR/UI/NotchWindowController.swift" \
  "$SOURCES_DIR/UI/Expanded/HeaderRow.swift" \
  "$SOURCES_DIR/UI/Expanded/ResetSubtitleRow.swift" \
  "$SOURCES_DIR/UI/Expanded/SessionCard.swift" \
  "$SOURCES_DIR/UI/Expanded/WeeklyCard.swift" \
  "$SOURCES_DIR/UI/Expanded/UsageChartView.swift" \
  "$SOURCES_DIR/UI/Expanded/InlineSettingsView.swift" \
  "$SOURCES_DIR/UI/Expanded/ExpandedPanelView.swift" \
  "$SOURCES_DIR/UI/Onboarding/OnboardingView.swift" \
  "$SOURCES_DIR/UI/NotificationBanner.swift"

echo -e "${BLUE}==> Assembling .app bundle${NC}"

# Info.plist — resolve Xcode build variables to literal values
cp "$SOURCES_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME"                     "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.claudeusagenotch.ClaudeUsageNotch"   "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_CONTENTS/Info.plist"

# Brand logos — must run before iconutil (which may fail) so the notch loads the right mark.
if [ -f "$SOURCES_DIR/Resources/BrandIcons/brand-claude.png" ]; then
  cp "$SOURCES_DIR/Resources/BrandIcons/brand-claude.png" "$APP_CONTENTS/Resources/"
fi

# App icon — build .icns from the PNG set using iconutil (best-effort)
ICONSET="/tmp/$APP_NAME.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
sips -z 16   16   "$ASSETS_DIR/AppIcon-16.png"   --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32   32   "$ASSETS_DIR/AppIcon-32.png"   --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32   32   "$ASSETS_DIR/AppIcon-32.png"   --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64   64   "$ASSETS_DIR/AppIcon-64.png"   --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128  128  "$ASSETS_DIR/AppIcon-128.png"  --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256  256  "$ASSETS_DIR/AppIcon-256.png"  --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$ASSETS_DIR/AppIcon-256.png"  --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512  512  "$ASSETS_DIR/AppIcon-512.png"  --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$ASSETS_DIR/AppIcon-512.png"  --out "$ICONSET/icon_512x512.png"    >/dev/null
sips -z 1024 1024 "$ASSETS_DIR/AppIcon-1024.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
if iconutil -c icns "$ICONSET" -o "$APP_CONTENTS/Resources/AppIcon.icns" 2>/dev/null; then
  echo -e "${GREEN}    AppIcon.icns OK${NC}"
else
  echo -e "${YELLOW}    (iconutil skipped — dock icon may be missing)${NC}"
fi

# Strip quarantine attribute so macOS doesn't block launch
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo -e "${BLUE}==> Signing bundle with: $SIGN_IDENTITY${NC}"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE" \
    && codesign --verify --strict "$APP_BUNDLE" \
    && echo -e "${GREEN}    signature OK${NC}" \
    || { echo -e "${RED}Signing failed — check that the cert is valid in Keychain.${NC}" >&2; exit 1; }
else
  echo -e "${BLUE}==> Ad-hoc signing (no SIGN_IDENTITY set)${NC}"
  codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}==> Built: $APP_BUNDLE${NC}"
echo -e "${YELLOW}    Run with: open $APP_BUNDLE${NC}"
