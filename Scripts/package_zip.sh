#!/usr/bin/env bash
set -euo pipefail

# Build PinDock.app and zip it for GitHub Releases (no DMG needed).
# Users: unzip → drag PinDock.app to Applications.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo "1.0.0")"
APP_NAME="PinDock"
ZIP_NAME="PinDock-${VERSION}.zip"
ZIP_PATH="${ROOT}/${ZIP_NAME}"
STAGE="$(mktemp -d "/tmp/pindock-zip.XXXXXX")"

cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT

export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

echo "==> Building app…"
chmod +x Scripts/package_app.sh
./Scripts/package_app.sh

APP_SRC="${ROOT}/${APP_NAME}.app"
if [[ ! -x "${APP_SRC}/Contents/MacOS/${APP_NAME}" ]]; then
  echo "ERROR: missing ${APP_SRC}" >&2
  exit 1
fi

# Stage a clean copy (no resource forks / quarantine)
ditto --norsrc --noextattr "${APP_SRC}" "${STAGE}/${APP_NAME}.app"
xattr -cr "${STAGE}/${APP_NAME}.app" 2>/dev/null || true
find "${STAGE}" -name '._*' -delete 2>/dev/null || true

echo "==> Creating ${ZIP_NAME}…"
rm -f "${ZIP_PATH}"
# ditto zip keeps .app structure correctly for macOS
ditto -c -k --sequesterRsrc --keepParent "${STAGE}/${APP_NAME}.app" "${ZIP_PATH}"

echo ""
echo "Done: ${ZIP_PATH} ($(du -sh "${ZIP_PATH}" | awk '{print $1}'))"
echo "Install: unzip, then drag PinDock.app into Applications"
echo ""
