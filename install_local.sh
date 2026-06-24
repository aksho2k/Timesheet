#!/bin/bash
# install_local.sh - build and install Timesheet.app to ~/Apps for local development.
set -euo pipefail

SCHEME="Timesheet"
PROJECT="Timesheet.xcodeproj"

# Build
echo "Building $SCHEME (Debug)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  build \
  2>&1 | grep -E "^(error:|warning:|\*\* BUILD)" || true

# Locate built .app in DerivedData
APP_SRC=$(find "$HOME/Library/Developer/Xcode/DerivedData/Timesheet-"*/Build/Products/Debug/Timesheet.app \
  -maxdepth 0 2>/dev/null | head -1)

if [[ -z "$APP_SRC" ]]; then
  echo "ERROR: Could not find Timesheet.app in DerivedData. Check build errors above."
  exit 1
fi

echo "Source: $APP_SRC"

# Install
echo "Installing to /Users/akshobhya/Apps/Timesheet.app..."
mkdir -p /Users/akshobhya/Apps
rm -rf /Users/akshobhya/Apps/Timesheet.app
cp -R "$APP_SRC" /Users/akshobhya/Apps/Timesheet.app

# Strip quarantine
echo "Removing quarantine attribute..."
xattr -dr com.apple.quarantine /Users/akshobhya/Apps/Timesheet.app

echo ""
echo "Done: /Users/akshobhya/Apps/Timesheet.app"
echo ""
echo "To restart the app:"
echo "  killall Timesheet 2>/dev/null || true && open /Users/akshobhya/Apps/Timesheet.app"
