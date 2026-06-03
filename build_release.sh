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
ZIP_OUTPUT="Timesheet.zip"
EXPORT_PLIST="ExportOptions.plist"

# ── Clean previous build artefacts ────────────────────────────────────────────
rm -rf build "$ZIP_OUTPUT"
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
  | grep -E "^(error:|warning:|archive:|Build succeeded|** BUILD)" || true

# ── Export ────────────────────────────────────────────────────────────────────
echo "▸ Exporting signed .app…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  | grep -E "^(error:|warning:|Export succeeded|** BUILD)" || true

APP="$EXPORT_PATH/Timesheet.app"
if [[ ! -d "$APP" ]]; then
  echo "✗ Export failed — $APP not found. Check ExportOptions.plist and your signing certificate."
  exit 1
fi

# ── Zip (ditto preserves code signature and resource forks) ───────────────────
echo "▸ Zipping…"
ditto -c -k --keepParent "$APP" "$ZIP_OUTPUT"

# ── Summary ───────────────────────────────────────────────────────────────────
SIZE=$(du -sh "$ZIP_OUTPUT" | cut -f1)
echo ""
echo "✓ Done: $ZIP_OUTPUT ($SIZE)"
echo ""
echo "Next steps:"
echo "  1. Notarize (recommended): xcrun notarytool submit $ZIP_OUTPUT --keychain-profile <profile> --wait"
echo "  2. Create a GitHub release and upload $ZIP_OUTPUT as the release asset."
