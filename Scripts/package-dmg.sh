#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nivlo"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
BUILD_CONFIG="${BUILD_CONFIG:-release}"

if [[ -n "${VERSION:-}" ]]; then
  APP_VERSION="${VERSION}"
elif git -C "${ROOT_DIR}" describe --tags --abbrev=0 >/dev/null 2>&1; then
  APP_VERSION="$(git -C "${ROOT_DIR}" describe --tags --abbrev=0 | sed 's/^v//')"
else
  APP_VERSION="0.0.0-dev"
fi

echo "Building ${APP_NAME} (${APP_VERSION}) in ${BUILD_CONFIG} mode..."
cd "${ROOT_DIR}"
swift build -c "${BUILD_CONFIG}" --product Nivlo

EXECUTABLE="${ROOT_DIR}/.build/${BUILD_CONFIG}/${APP_NAME}"
if [[ ! -f "${EXECUTABLE}" ]]; then
  echo "Missing executable at ${EXECUTABLE}" >&2
  exit 1
fi

rm -rf "${APP_DIR}" "${DMG_PATH}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

ICON_SOURCE="${ROOT_DIR}/Packaging/AppIcon-1024.png"
ICONSET="${DIST_DIR}/AppIcon.iconset"
if [[ -f "${ICON_SOURCE}" ]]; then
  rm -rf "${ICONSET}"
  mkdir -p "${ICONSET}"
  for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${ICON_SOURCE}" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" "${ICON_SOURCE}" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
  rm -rf "${ICONSET}"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>dev.nivlo</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

STAGING_DIR="${DIST_DIR}/dmg-staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_DIR}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

rm -rf "${STAGING_DIR}"

echo "Created ${APP_DIR}"
echo "Created ${DMG_PATH}"
