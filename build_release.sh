#!/bin/bash
# build_release.sh — archives, exports, and zips a signed Timesheet.app
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

# ── DMG (drag-to-Applications) ────────────────────────────────────────────────
echo "▸ Building DMG…"
STAGING="build/dmg_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"

# Copy the signed .app and add an Applications symlink for drag-install
cp -R "$APP" "$STAGING/Timesheet.app"
ln -s /Applications "$STAGING/Applications"

# Create a compressed, internet-ready DMG
hdiutil create \
  -volname "Timesheet" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_OUTPUT"

# ── Summary ───────────────────────────────────────────────────────────────────
SIZE=$(du -sh "$DMG_OUTPUT" | cut -f1)
echo ""
echo "✓ Done: $DMG_OUTPUT ($SIZE)"
echo ""
echo "Next steps:"
echo "  1. Notarize (recommended): xcrun notarytool submit $DMG_OUTPUT --keychain-profile <profile> --wait"
echo "  2. Create a GitHub release and upload $DMG_OUTPUT as the release asset."
