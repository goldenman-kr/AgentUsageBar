#!/usr/bin/env bash
# Verifies the data pipeline: unit tests + a live probe against the real API
# (reads your Claude Code Keychain token).
set -euo pipefail
cd "$(dirname "$0")/../Packages/ClaudeUsageCore"

echo "▶︎ Unit tests"
swift test

echo
echo "▶︎ Live probe (real Keychain token + api.anthropic.com/api/oauth/usage)"
swift run usage-probe
