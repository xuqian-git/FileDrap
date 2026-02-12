#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME_NAME="FileDrap"
PROJECT_NAME="FileDrap"
APP_PRODUCT_NAME="FileDrap"
DIST_NAME="文件拖拖"
ENTITLEMENTS="$ROOT/Sources/FileDrap/FileDrap.entitlements"
BUILD_ROOT="$ROOT/build/local"
DERIVED="$BUILD_ROOT/DerivedData"
DIST="$ROOT/dist"
DMG_ROOT="$BUILD_ROOT/dmg-root"
STAMP="$(date +%Y%m%d-%H%M%S)"

cd "$ROOT"

# Keep Xcode UI signing settings stable by default.
# Set REGENERATE_PROJECT=1 only when you intentionally want to regenerate .xcodeproj from project.yml.
if [[ "${REGENERATE_PROJECT:-0}" == "1" ]]; then
  xcodegen generate >/dev/null
fi

COMMON_BUILD_ARGS=(
  -project "$PROJECT_NAME.xcodeproj"
  -scheme "$SCHEME_NAME"
  -configuration Release
  -sdk macosx
  -derivedDataPath "$DERIVED"
)

SIGNED_BUILD_OK=0
echo "Trying signed build from current Xcode project settings..."
if xcodebuild "${COMMON_BUILD_ARGS[@]}" build >/dev/null; then
  SIGNED_BUILD_OK=1
  echo "Signed build succeeded."
else
  echo "Signed build failed. Falling back to unsigned build..."
  xcodebuild "${COMMON_BUILD_ARGS[@]}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >/dev/null
fi

APP_SRC="$DERIVED/Build/Products/Release/$APP_PRODUCT_NAME.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Build output missing: $APP_SRC" >&2
  exit 1
fi

if [[ "$SIGNED_BUILD_OK" -eq 0 ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\\(Developer ID Application:.*\\)".*/\\1/p' \
      | head -n 1
  )"

  if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(
      security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\\(Apple Development:.*\\)".*/\\1/p' \
        | head -n 1
    )"
  fi

  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "Post-signing fallback build with identity: $SIGN_IDENTITY"
    /usr/bin/codesign \
      --force \
      --deep \
      --options runtime \
      --timestamp \
      --entitlements "$ENTITLEMENTS" \
      --sign "$SIGN_IDENTITY" \
      "$APP_SRC"
  else
    echo "No signing identity found; package remains unsigned."
  fi
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
