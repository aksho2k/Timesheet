#!/bin/bash
# release.sh - build, tag, and publish a new GitHub release with the DMG attached.
#
# Usage:
#   chmod +x release.sh
#   ./release.sh 1.0.1
#
# Prerequisites:
#   - A GitHub personal access token in .github_token (never committed, gitignored)
#   - git remote "origin" pointing to https://github.com/aksho2k/Timesheet
#   - build_release.sh present and working in the same directory

set -euo pipefail

REPO="aksho2k/Timesheet"
DMG="Timesheet.dmg"
TOKEN_FILE=".github_token"

# ----------------------------------------------------------------------------
# 1. Validate arguments
# ----------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version>   (e.g. $0 1.0.1)"
  exit 1
fi

VERSION="$1"
TAG="v$VERSION"

# ----------------------------------------------------------------------------
# 2. Load GitHub token
# ----------------------------------------------------------------------------
if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "ERROR: $TOKEN_FILE not found."
  echo "Create it with your GitHub personal access token (one line, no spaces):"
  echo "  echo 'ghp_yourtoken' > .github_token"
  exit 1
fi

GH_TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")

if [[ -z "$GH_TOKEN" ]]; then
  echo "ERROR: $TOKEN_FILE is empty."
  exit 1
fi

echo "--- Step 1: Building release DMG ---"
./build_release.sh

if [[ ! -f "$DMG" ]]; then
  echo "ERROR: $DMG not produced by build_release.sh"
  exit 1
fi

echo ""
echo "--- Step 2: Committing changes ---"
git add -A
# Only commit if there is actually something staged
if git diff --cached --quiet; then
  echo "Nothing to commit, working tree clean."
else
  git commit -m "Release $VERSION"
fi

echo ""
echo "--- Step 3: Pushing to origin main ---"
git push origin main

echo ""
echo "--- Step 4: Tagging $TAG and pushing ---"
# Delete local tag if it already exists (re-release case)
git tag -d "$TAG" 2>/dev/null || true
git tag "$TAG"
git push origin "$TAG"

echo ""
echo "--- Step 5: Creating GitHub release via API ---"

RELEASE_JSON=$(curl -sf \
  -X POST \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO/releases" \
  -d "{
    \"tag_name\": \"$TAG\",
    \"name\": \"$VERSION\",
    \"body\": \"## Timesheet $VERSION\n\nDownload Timesheet.dmg below, open it, and drag Timesheet.app to Applications.\",
    \"draft\": false,
    \"prerelease\": false
  }")

RELEASE_ID=$(echo "$RELEASE_JSON" | grep '"id"' | head -1 | sed 's/[^0-9]//g')

if [[ -z "$RELEASE_ID" ]]; then
  echo "ERROR: Failed to create GitHub release. API response:"
  echo "$RELEASE_JSON"
  exit 1
fi

echo "Release created (id=$RELEASE_ID)"

echo ""
echo "--- Step 6: Uploading $DMG as release asset ---"

UPLOAD_URL="https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$DMG"

UPLOAD_RESPONSE=$(curl -sf \
  -X POST \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/x-apple-diskimage" \
  --data-binary @"$DMG" \
  "$UPLOAD_URL")

ASSET_URL=$(echo "$UPLOAD_RESPONSE" | grep '"browser_download_url"' | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')

if [[ -z "$ASSET_URL" ]]; then
  echo "ERROR: DMG upload may have failed. API response:"
  echo "$UPLOAD_RESPONSE"
  exit 1
fi

echo ""
echo "================================================================"
echo "Released: https://github.com/$REPO/releases/tag/$TAG"
echo "Download: $ASSET_URL"
echo "================================================================"
