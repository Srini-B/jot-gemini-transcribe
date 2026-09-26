#!/bin/bash
# Copyright 2026 Google LLC
# Licensed under the Apache License, Version 2.0.

# Build, sign, notarize, staple, and package VoiceiQ.
# The caller must source ~/.zshrc first. This script never prints credentials.
set -euo pipefail
cd "$(dirname "$0")/.."

for variable in APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID; do
  if [[ -z "${!variable:-}" ]]; then
    echo "error: $variable is unset; source ~/.zshrc before running this script." >&2
    exit 1
  fi
done

VERSION=$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' project.yml)
BUILD_DIR="build/release"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_NAME="VoiceiQ"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/VoiceiQ-$VERSION.zip"
DMG_PATH="$BUILD_DIR/VoiceiQ-$VERSION.dmg"
SIGN_IDENTITY="Developer ID Application"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▸ Generating project"
xcodegen generate

echo "▸ Building Developer ID Release"
env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild build \
    -project VoiceIQ.xcodeproj \
    -scheme VoiceIQ \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM=G8K3545FJ2 \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS=--timestamp \
    -quiet

[[ -d "$APP_PATH" ]] || { echo "error: build produced no app at $APP_PATH" >&2; exit 1; }

echo "▸ Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvv "$APP_PATH"
if codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q 'get-task-allow'; then
  echo "error: get-task-allow is present in the Release app." >&2
  exit 1
fi

echo "▸ Notarizing app"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait
xcrun stapler staple "$APP_PATH"
spctl -a -t exec -vv "$APP_PATH"
# Re-zip after stapling so the zip is shareable on its own: Gatekeeper on an
# offline Mac reads the stapled ticket instead of asking Apple.
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "▸ Building and signing DMG"
APP_NAME="$APP_NAME" scripts/make-dmg.sh "$APP_PATH" "$DMG_PATH"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

echo "▸ Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait
xcrun stapler staple "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

echo "✓ $DMG_PATH"
