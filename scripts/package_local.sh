#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME_NAME="FileDrap"
PROJECT_NAME="FileDrap"
APP_PRODUCT_NAME="FileDrap"
DIST_NAME="文件拖拖"
BUILD_ROOT="$ROOT/build/local"
DERIVED="$BUILD_ROOT/DerivedData"
DIST="$ROOT/dist"
DMG_ROOT="$BUILD_ROOT/dmg-root"
STAMP="$(date +%Y%m%d-%H%M%S)"

cd "$ROOT"

xcodegen generate >/dev/null

xcodebuild \
  -project "$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build >/dev/null

APP_SRC="$DERIVED/Build/Products/Release/$APP_PRODUCT_NAME.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Build output missing: $APP_SRC" >&2
  exit 1
fi

rm -rf "$DIST" "$DMG_ROOT"
mkdir -p "$DIST"
cp -R "$APP_SRC" "$DIST/$DIST_NAME.app"

mkdir -p "$DMG_ROOT"
cp -R "$DIST/$DIST_NAME.app" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
cat > "$DMG_ROOT/安装说明.txt" <<EOF
将「$DIST_NAME.app」拖动到「Applications」文件夹完成安装。
EOF

ZIP_PATH="$DIST/${DIST_NAME}-local-${STAMP}.zip"
DMG_PATH="$DIST/${DIST_NAME}-local-${STAMP}.dmg"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DIST/$DIST_NAME.app" "$ZIP_PATH"
/usr/bin/hdiutil create -volname "$DIST_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "App: $DIST/$DIST_NAME.app"
echo "Zip: $ZIP_PATH"
echo "Dmg: $DMG_PATH"
