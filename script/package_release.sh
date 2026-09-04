#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---unsigned}"
VERSION="${2:-}"
APP_NAME="DevBar"
BUNDLE_ID="io.github.madhangokul.devbar"
MIN_SYSTEM_VERSION="13.0"

if [[ "$MODE" != "--unsigned" && "$MODE" != "--signed" && "$MODE" != "--notarize" ]]; then
  echo "usage: $0 [--unsigned|--signed|--notarize] <version>" >&2
  exit 2
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "error: version must look like 1.0.0 or 1.0.0-beta.1" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-universal.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
ENTITLEMENTS="$ROOT_DIR/support/DevBar.entitlements"
ICON_SOURCE="$ROOT_DIR/support/DevBar.icns"

case "$MODE" in
  --signed|--notarize)
    if [[ -z "${DEVBAR_CODESIGN_IDENTITY:-}" ]]; then
      echo "error: DEVBAR_CODESIGN_IDENTITY is required for $MODE" >&2
      exit 1
    fi
    ;;
esac

if [[ "$MODE" == "--notarize" && -z "${DEVBAR_NOTARY_PROFILE:-}" ]]; then
  echo "error: DEVBAR_NOTARY_PROFILE is required for --notarize" >&2
  exit 1
fi

cd "$ROOT_DIR"
echo "Building universal release binary…"
swift build --configuration release --product "$APP_NAME" --arch arm64 --arch x86_64
BUILD_DIR="$(swift build --configuration release --show-bin-path --arch arm64 --arch x86_64)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "error: release binary not found at $BUILD_BINARY" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE" "$DMG_ROOT" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_ROOT"
cp "$BUILD_BINARY" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

ICON_PLIST_ENTRY=""
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$RESOURCES_DIR/DevBar.icns"
  ICON_PLIST_ENTRY=$'    <key>CFBundleIconFile</key>\n    <string>DevBar</string>'
fi

cat >"$CONTENTS_DIR/Info.plist" <<PLIST
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
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>${DEVBAR_BUILD_NUMBER:-1}</string>
$ICON_PLIST_ENTRY
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_SYSTEM_VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist" "$ENTITLEMENTS"
lipo -info "$MACOS_DIR/$APP_NAME"

if [[ "$MODE" == "--unsigned" ]]; then
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVBAR_CODESIGN_IDENTITY" \
    "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

cp -R "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$MODE" != "--unsigned" ]]; then
  codesign --force --timestamp --sign "$DEVBAR_CODESIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$MODE" == "--notarize" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$DEVBAR_NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type execute --verbose=4 "$APP_BUNDLE"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" >"$(basename "$CHECKSUM_PATH")"
)

rm -rf "$DMG_ROOT"

echo
echo "Created: $DMG_PATH"
echo "Checksum: $CHECKSUM_PATH"
if [[ "$MODE" == "--unsigned" ]]; then
  echo "Warning: this ad-hoc signed DMG is for local testing only."
fi
