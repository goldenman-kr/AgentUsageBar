#!/usr/bin/env bash
# Full signed build (menu-bar app + WidgetKit widget) with App Groups.
# Requires an Apple Developer team (free personal team is fine for local use).
#
#   DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build.sh
#
# Find your team IDs with:  security find-identity -v -p codesigning
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM=YourTeamID — see: security find-identity -v -p codesigning}"
CONFIG="${CONFIG:-Release}"

xcodegen generate
echo "▶︎ Building $CONFIG with team $DEVELOPMENT_TEAM (auto-managed signing)…"
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsageBar -configuration "$CONFIG" \
    -derivedDataPath build \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    -allowProvisioningUpdates \
    build

APP="build/Build/Products/$CONFIG/ClaudeUsageBar.app"
echo
echo "✓ Built: $APP"
echo "  Install:  cp -R \"$APP\" /Applications/  &&  open /Applications/ClaudeUsageBar.app"
echo "  Then add the widget: Notification Center → 위젯 편집 → Claude 사용량,"
echo "  or right-click the desktop → 위젯 편집."
