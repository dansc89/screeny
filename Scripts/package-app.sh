#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Screeny"
BUNDLE_ID="com.screeny.app"
BUILD_DIR=".build/release"
BIN_PATH="$BUILD_DIR/$APP_NAME"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
INSTALL_APP_PATH="${SCREENY_INSTALL_APP_PATH:-$HOME/Applications/$APP_NAME.app}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"

VERSION_TAG="${SCREENY_VERSION_TAG:-$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.1.0")}"
APP_VERSION="${VERSION_TAG#v}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  APP_VERSION="0.1.0"
fi
BUILD_NUMBER="${SCREENY_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo "1")}"
SIGN_IDENTITY="${SCREENY_CODESIGN_IDENTITY:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n1)"
fi

echo "Building release binary..."
swift build -c release

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Expected binary not found at $BIN_PATH"
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "Generating app icon..."
swift Scripts/generate-icon.swift "$ICON_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing app bundle with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "No Developer ID identity found. Using ad-hoc signing."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

mkdir -p "$(dirname "$INSTALL_APP_PATH")"
rm -rf "$INSTALL_APP_PATH"
cp -R "$APP_DIR" "$INSTALL_APP_PATH"

echo "Installed app bundle: $INSTALL_APP_PATH"
echo "Build artifact: $APP_DIR"
