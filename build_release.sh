#!/bin/bash
# build_release.sh — archives, exports, and packages a signed Timesheet.app as a DMG
#
# Prerequisites:
#   • Xcode command-line tools installed  (xcode-select --install)
#   • Developer ID Application certificate in your keychain
#     (verify with: security find-identity -v -p codesigning)
#   • ExportOptions.plist present in the project root (already committed)
#
# Usage:
#   chmod +x build_release.sh
#   ./build_release.sh
#
# Output: Timesheet.zip in the project root

set -euo pipefail

SCHEME="Timesheet"
PROJECT="Timesheet.xcodeproj"
CONFIGURATION="Release"
ARCHIVE_PATH="build/Timesheet.xcarchive"
EXPORT_PATH="build/export"
DMG_OUTPUT="Timesheet.dmg"
EXPORT_PLIST="ExportOptions.plist"

# ── Clean previous build artefacts ────────────────────────────────────────────
rm -rf build "$DMG_OUTPUT"
mkdir -p build

# ── Archive ───────────────────────────────────────────────────────────────────
echo "▸ Archiving ($CONFIGURATION)…"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  ONLY_ACTIVE_ARCH=NO \
  2>&1 | grep -E "^(error:|warning:|archive:|\*\* BUILD)" || true

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "✗ Archive not found at $ARCHIVE_PATH — check errors above."
  exit 1
fi

# ── Export ────────────────────────────────────────────────────────────────────
echo "▸ Exporting signed .app…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  2>&1 | grep -E "^(error:|warning:|Export succeeded|\*\* BUILD)" || true

APP="$EXPORT_PATH/Timesheet.app"
if [[ ! -d "$APP" ]]; then
  echo "✗ Export failed — $APP not found. Check ExportOptions.plist and your signing certificate."
  exit 1
fi

# ── DMG (drag-to-Applications with custom window layout) ─────────────────────
echo "▸ Building DMG…"

VOL_NAME="Timesheet"
STAGING="build/dmg_staging"
TEMP_DMG="build/Timesheet_rw.dmg"

rm -rf "$STAGING" "$TEMP_DMG"
mkdir -p "$STAGING"

# Populate staging: the app and an /Applications alias for drag-install
cp -R "$APP" "$STAGING/Timesheet.app"
ln -s /Applications "$STAGING/Applications"

# Step 1 — create a read/write image so Finder can write .DS_Store into it
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDRW \
  "$TEMP_DMG" > /dev/null

# Step 2 — mount quietly; capture the mount point for a clean unmount later
hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  "$TEMP_DMG" > /dev/null 2>&1

MOUNT_POINT="/Volumes/$VOL_NAME"
if [[ ! -d "$MOUNT_POINT" ]]; then
  echo "✗ Could not mount $TEMP_DMG"
  exit 1
fi

sleep 2   # give Finder time to fully register the new volume

# Step 3 — use Finder (via osascript) to set window size, icon positions,
#           icon size, and a plain light-grey background.
#           No external tools required — hdiutil and osascript both ship with macOS.
osascript << APPLESCRIPT
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {400, 100, 900, 430}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set background color of viewOptions to {62000, 62000, 62000}
    set position of item "Timesheet.app" of container window to {150, 165}
    set position of item "Applications" of container window to {350, 165}
    update without registering applications
    delay 3
    close
  end tell
end tell
APPLESCRIPT

sync          # flush kernel buffers
sleep 2       # let Finder finish writing .DS_Store to the volume

# Step 4 — unmount cleanly via mount point (more reliable than device node)
hdiutil detach "$MOUNT_POINT" -quiet

# Step 5 — convert to a compressed, read-only internet-ready image
hdiutil convert "$TEMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_OUTPUT" > /dev/null

rm -f "$TEMP_DMG"

# ── Summary ───────────────────────────────────────────────────────────────────
SIZE=$(du -sh "$DMG_OUTPUT" | cut -f1)
echo ""
echo "✓ Done: $DMG_OUTPUT ($SIZE)"
echo ""
echo "Next steps:"
echo "  1. Notarize (recommended): xcrun notarytool submit $DMG_OUTPUT --keychain-profile <profile> --wait"
echo "  2. Create a GitHub release and upload $DMG_OUTPUT as the release asset."
