#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nivlo"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_RW_PATH="${DIST_DIR}/${APP_NAME}-temp.dmg"
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

rm -rf "${APP_DIR}" "${DMG_PATH}" "${DMG_RW_PATH}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

ICON_SOURCE="${ROOT_DIR}/Packaging/AppIcon-1024.png"
ICON_SQUARE="${DIST_DIR}/AppIcon-1024-square.png"
ICONSET="${DIST_DIR}/AppIcon.iconset"
if [[ -f "${ICON_SOURCE}" ]]; then
  swift "${ROOT_DIR}/Scripts/prepare-app-icon.swift" "${ICON_SOURCE}" "${ICON_SQUARE}"
  rm -rf "${ICONSET}"
  mkdir -p "${ICONSET}"
  for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${ICON_SQUARE}" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" "${ICON_SQUARE}" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
  cp "${APP_DIR}/Contents/Resources/AppIcon.icns" "${ROOT_DIR}/Packaging/AppIcon.icns"
  cp "${APP_DIR}/Contents/Resources/AppIcon.icns" "${ROOT_DIR}/Sources/NivloApp/Resources/AppIcon.icns"
  rm -rf "${ICONSET}" "${ICON_SQUARE}"
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
BACKGROUND_DIR="${STAGING_DIR}/.background"
rm -rf "${STAGING_DIR}"
mkdir -p "${BACKGROUND_DIR}"
swift "${ROOT_DIR}/Scripts/generate-dmg-background.swift" "${BACKGROUND_DIR}/background.png"
cp -R "${APP_DIR}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

DMG_SIZE_MB=$(( $(du -sm "${STAGING_DIR}" | awk '{print $1}') + 40 ))

close_finder_windows_for_volume() {
  local volume_name="$1"
  osascript <<EOF >/dev/null 2>&1 || true
tell application "Finder"
  try
    close every window whose name is "${volume_name}"
  end try
end tell
EOF
}

detach_dmg_volume() {
  local mount_path="$1"
  local attempt

  for attempt in $(seq 1 12); do
    if hdiutil detach "${mount_path}" >/dev/null 2>&1; then
      return 0
    fi

    close_finder_windows_for_volume "${APP_NAME}"
    sync
    sleep 2
  done

  echo "Force-detaching ${mount_path}..." >&2
  hdiutil detach "${mount_path}" -force
}

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDRW \
  -size "${DMG_SIZE_MB}m" \
  "${DMG_RW_PATH}" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify "${DMG_RW_PATH}")"
VOLUME_PATH="$(echo "${MOUNT_OUTPUT}" | awk '/\/Volumes\// {print $3; exit}')"
if [[ -z "${VOLUME_PATH}" ]]; then
  echo "Failed to mount temporary DMG" >&2
  exit 1
fi

cleanup_dmg_mount() {
  if [[ -n "${VOLUME_PATH:-}" && -d "${VOLUME_PATH}" ]]; then
    detach_dmg_volume "${VOLUME_PATH}" || true
  fi
}
trap cleanup_dmg_mount EXIT

osascript "${ROOT_DIR}/Scripts/configure-dmg.applescript" "${APP_NAME}" "${APP_NAME}"
close_finder_windows_for_volume "${APP_NAME}"
sync
sleep 1

detach_dmg_volume "${VOLUME_PATH}"
trap - EXIT
VOLUME_PATH=""

hdiutil convert "${DMG_RW_PATH}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" >/dev/null
rm -f "${DMG_RW_PATH}"
rm -rf "${STAGING_DIR}"

echo "Created ${APP_DIR}"
echo "Created ${DMG_PATH}"
