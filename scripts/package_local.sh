#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FileDrap"
BUILD_ROOT="$ROOT/build/local"
DERIVED="$BUILD_ROOT/DerivedData"
DIST="$ROOT/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"

cd "$ROOT"

xcodegen generate >/dev/null

xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build >/dev/null

APP_SRC="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Build output missing: $APP_SRC" >&2
  exit 1
fi

rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$APP_SRC" "$DIST/"

ZIP_PATH="$DIST/${APP_NAME}-local-${STAMP}.zip"
DMG_PATH="$DIST/${APP_NAME}-local-${STAMP}.dmg"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DIST/$APP_NAME.app" "$ZIP_PATH"
/usr/bin/hdiutil create -volname "$APP_NAME" -srcfolder "$DIST/$APP_NAME.app" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "App: $DIST/$APP_NAME.app"
echo "Zip: $ZIP_PATH"
echo "Dmg: $DMG_PATH"
