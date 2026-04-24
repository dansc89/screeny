#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <app_path> <output_dmg> [volume_name]"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="$1"
OUTPUT_DMG="$2"
VOLUME_NAME="${3:-Screeny}"
APP_BASENAME="$(basename "$APP_PATH")"
VOLUME_ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
SIGN_IDENTITY="${SCREENY_CODESIGN_IDENTITY:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n1)"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install with: brew install create-dmg"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
STAGING_DIR="$TMP_DIR/staging"
BACKGROUND_PATH="$TMP_DIR/background.png"
APPS_ALIAS_PATH="$TMP_DIR/Applications.alias"
README_PATH="$TMP_DIR/README - IMPORTANT.txt"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
swift Scripts/generate-dmg-background.swift "$BACKGROUND_PATH"
cat > "$README_PATH" <<'README'
Screeny Setup (Important)
=========================

To use Screeny's keyboard shortcuts (Cmd+Shift+3 and Cmd+Shift+4),
disable the default macOS screenshot shortcuts first.

System Settings > Keyboard > Keyboard Shortcuts > Screenshots

Turn off the macOS defaults for:
- Save picture of screen as a file
- Save picture of selected area as a file

Then launch Screeny from Applications and grant Screen Recording permission if prompted.
README

osascript <<OSA >/dev/null 2>/dev/null || true
tell application "Finder"
  set aliasContainer to POSIX file "$TMP_DIR" as alias
  make new alias file at aliasContainer to POSIX file "/Applications" with properties {name:"Applications.alias"}
end tell
OSA
if [[ ! -e "$APPS_ALIAS_PATH" ]]; then
  ln -s /Applications "$APPS_ALIAS_PATH"
fi

rm -f "$OUTPUT_DMG"
mkdir -p "$(dirname "$OUTPUT_DMG")"

run_create_dmg() {
  local volicon_args=()
  if [[ -f "$VOLUME_ICON_PATH" ]]; then
    volicon_args=(--volicon "$VOLUME_ICON_PATH")
  fi

  create-dmg \
    --volname "$VOLUME_NAME" \
    "${volicon_args[@]}" \
    --window-pos 120 120 \
    --window-size 900 540 \
    --background "$BACKGROUND_PATH" \
    --icon-size 120 \
    --icon "$APP_BASENAME" 210 300 \
    --hide-extension "$APP_BASENAME" \
    --add-file "README - IMPORTANT.txt" "$README_PATH" 445 300 \
    --add-file "Applications" "$APPS_ALIAS_PATH" 680 300 \
    "$@" \
    "$OUTPUT_DMG" \
    "$STAGING_DIR"
}

if ! run_create_dmg; then
  echo "create-dmg Finder layout timed out, retrying in sandbox-safe mode..."
  rm -f "$OUTPUT_DMG"
  run_create_dmg --skip-jenkins --sandbox-safe
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing DMG with: $SIGN_IDENTITY"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUTPUT_DMG"
  codesign --verify --verbose=2 "$OUTPUT_DMG"
fi

echo "Created DMG: $OUTPUT_DMG"
