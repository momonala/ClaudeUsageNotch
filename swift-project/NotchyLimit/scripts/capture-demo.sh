#!/usr/bin/env bash
# capture-demo.sh — capture a GIF demo of Notchy Limit
#
# REQUIREMENTS:
#   1. Grant Screen Recording permission to Terminal (or iTerm2):
#      System Settings → Privacy & Security → Screen Recording → enable your terminal
#   2. brew install ffmpeg
#   3. The app must be running: open build/NotchyLimit.app
#
# OUTPUT:
#   docs/demo.gif   — 800px-wide optimised GIF (~1–2 MB)
#   docs/demo.mp4   — full quality MP4 (for README embed on GitHub)
#
# HOW TO EMBED IN README.md:
#   ![Notchy Limit demo](docs/demo.gif)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FRAMES_DIR="$PROJECT_DIR/docs/frames"
DOCS_DIR="$PROJECT_DIR/docs"
mkdir -p "$FRAMES_DIR" "$DOCS_DIR"

echo "==> Checking requirements"
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "❌  ffmpeg not found. Install with: brew install ffmpeg" >&2; exit 1
fi
if ! command -v screencapture >/dev/null 2>&1; then
  echo "❌  screencapture not found (macOS only)" >&2; exit 1
fi

# Test screen recording permission
TMP_TEST="/tmp/notchy_screen_test.png"
if ! screencapture -x "$TMP_TEST" 2>/dev/null; then
  echo ""
  echo "❌  Screen Recording permission required."
  echo "    System Settings → Privacy & Security → Screen Recording"
  echo "    Enable your terminal app, then re-run this script."
  rm -f "$TMP_TEST"
  exit 1
fi
rm -f "$TMP_TEST"
echo "   Screen Recording: ✓"

# Clean old frames
rm -f "$FRAMES_DIR"/*.png

echo ""
echo "==> Starting capture sequence (8 frames)"
echo "    The app should be running. Move your mouse AWAY from the notch now."
echo "    The script will capture automatically."
echo ""
sleep 2

# ── Frame sequence ───────────────────────────────────────────────────────────
# 1. Compact pill (idle)
echo "  [1/8] Compact pill (idle)..."
screencapture -x "$FRAMES_DIR/01_compact.png"
sleep 1.5

# 2. Compact pill (idle, slight pause)
echo "  [2/8] Compact pill (hold)..."
screencapture -x "$FRAMES_DIR/02_compact_hold.png"
sleep 1.0

# 3-5. During expand — user manually hovers during these 3 seconds
echo "  [3-5/8] >>> HOVER OVER THE NOTCH NOW — you have 3 seconds <<<"
sleep 0.8
screencapture -x "$FRAMES_DIR/03_expanding.png"
sleep 0.7
screencapture -x "$FRAMES_DIR/04_expanding2.png"
sleep 0.7
screencapture -x "$FRAMES_DIR/05_expanded.png"

# 6. Expanded (hold)
echo "  [6/8] Expanded panel (hold)..."
sleep 1.5
screencapture -x "$FRAMES_DIR/06_expanded_hold.png"
sleep 1.0

# 7. Expanded (longer hold)
screencapture -x "$FRAMES_DIR/07_expanded_hold2.png"
sleep 1.0

# 8. Collapsing — user moves mouse away
echo "  [7-8/8] >>> MOVE MOUSE AWAY FROM NOTCH NOW <<<"
sleep 0.8
screencapture -x "$FRAMES_DIR/08_collapsing.png"
sleep 1.0

echo ""
echo "==> Cropping to notch area (top centre, 500x350 px)"
# Crop all frames to focus on the notch area.
# Adjust CROP_X/CROP_Y if needed for your resolution.
# On MBP 14" (3024x1964 native, 1512x982 points):
#   Notch centre X ~756, width 500, starting at ~506
#   Top Y 0, height 350
SCREEN_W=$(system_profiler SPDisplaysDataType 2>/dev/null | grep Resolution | head -1 | awk '{print $2}')
SCREEN_W=${SCREEN_W:-2560}  # fallback
CROP_W=500
CROP_H=350
CROP_X=$(( (SCREEN_W / 2) - (CROP_W / 2) ))
CROP_Y=0

for f in "$FRAMES_DIR"/*.png; do
  ffmpeg -y -i "$f" -vf "crop=${CROP_W}:${CROP_H}:${CROP_X}:${CROP_Y},scale=800:-1:flags=lanczos" \
    "${f%.png}_cropped.png" -loglevel quiet
done

echo "==> Building GIF"
ffmpeg -y \
  -framerate 2 \
  -pattern_type glob \
  -i "$FRAMES_DIR/*_cropped.png" \
  -vf "fps=8,scale=800:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" \
  -loop 0 \
  "$DOCS_DIR/demo.gif" \
  -loglevel quiet

echo "==> Building MP4"
ffmpeg -y \
  -framerate 2 \
  -pattern_type glob \
  -i "$FRAMES_DIR/*_cropped.png" \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -crf 22 \
  -vf "fps=12,scale=800:-2:flags=lanczos" \
  "$DOCS_DIR/demo.mp4" \
  -loglevel quiet

echo ""
GIF_SIZE=$(du -sh "$DOCS_DIR/demo.gif" | cut -f1)
MP4_SIZE=$(du -sh "$DOCS_DIR/demo.mp4" | cut -f1)
echo "==> Done!"
echo "    GIF  : $DOCS_DIR/demo.gif  ($GIF_SIZE)"
echo "    MP4  : $DOCS_DIR/demo.mp4  ($MP4_SIZE)"
echo ""
echo "Embed in README.md:"
echo '    ![Notchy Limit demo](docs/demo.gif)'
echo ""
echo "Clean up frames?"
read -p "    Delete frame PNGs? [y/N] " ans
if [[ "${ans,,}" == "y" ]]; then
  rm -rf "$FRAMES_DIR"
  echo "    Frames deleted."
fi
