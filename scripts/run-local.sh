#!/usr/bin/env bash
# Quick local trial of the MENU-BAR APP only — no Apple Developer team required.
#
# This ad-hoc-signs the app, so the App Group container is unavailable and the
# WidgetKit widget will not receive data (it'll show "메뉴바 앱을 실행하세요").
# The menu-bar app itself is fully functional. For the desktop/Notification
# Center widget, use ./scripts/build.sh with your team (see README).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
echo "▶︎ Building (unsigned)…"
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsageBar -configuration Debug \
    -derivedDataPath build CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="build/Build/Products/Debug/AgentUsageBar.app"
echo "▶︎ Ad-hoc signing…"
codesign --force -s - "$APP/Contents/PlugIns/AgentUsageWidget.appex" 2>/dev/null || true
codesign --force -s - "$APP"

echo "▶︎ Launching menu-bar app (look for the gauge in your menu bar; no Dock icon)."
echo "   First launch may prompt for Keychain access → choose “항상 허용 / Always Allow”."
echo "   Quit from the popover’s “종료” button, or: pkill -f AgentUsageBar"
open "$APP"
