#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Screeny"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
VERSION_TAG="${SCREENY_VERSION_TAG:-$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.1.0")}"
VERSION="${VERSION_TAG#v}"
DMG_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}.dmg"

./Scripts/package-app.sh
./Scripts/package-dmg.sh "$APP_PATH" "$DMG_PATH" "$APP_NAME"

if [[ "${SCREENY_NOTARIZE:-0}" == "1" ]]; then
  ./Scripts/notarize-release.sh "$APP_PATH" "$DMG_PATH"
else
  echo "Skipping notarization. Set SCREENY_NOTARIZE=1 to notarize and staple."
fi

echo "Release artifacts:"
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
