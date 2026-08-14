#!/usr/bin/env bash
set -euo pipefail

# Classic drag-to-Applications DMG (PinDock.app + Applications).
# Layout matches shipped 1.0.1 (.DS_Store template + Finder styling).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo "1.0.0")"
APP_NAME="PinDock"
VOL_NAME="PinDock Installer"
DMG_NAME="PinDock-${VERSION}"
WORK="$(mktemp -d "/tmp/pindock-dmg.XXXXXX")"
STAGE="${WORK}/stage"
RW_DMG="${WORK}/${DMG_NAME}.rw.dmg"
FINAL_DMG="${ROOT}/${DMG_NAME}.dmg"
BG_SRC="${ROOT}/Resources/dmg/background.png"
DS_TEMPLATE="${ROOT}/Resources/dmg/DS_Store"
MOUNT=""
KC_PATH="$(cd "${ROOT}/Scripts/certs" && pwd)/PinDock.keychain-db"
IDENTITY_NAME="${PINDOCK_IDENTITY_NAME:-PinDock Development}"

cleanup() {
  if [[ -n "${MOUNT}" ]]; then
    hdiutil detach "${MOUNT}" -force >/dev/null 2>&1 || true
  fi
  for v in "/Volumes/${VOL_NAME}" "/Volumes/PinDock" "/Volumes/PinDock 1" \
           "/Volumes/PinDock Installer" "/Volumes/PinDock Installer 1"; do
    hdiutil detach "$v" -force >/dev/null 2>&1 || true
  done
  rm -rf "${WORK}"
}
trap cleanup EXIT

export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

echo "==> Building app…"
chmod +x Scripts/package_app.sh Scripts/ensure_signing_identity.sh
./Scripts/package_app.sh

APP_SRC="${ROOT}/${APP_NAME}.app"
if [[ ! -x "${APP_SRC}/Contents/MacOS/${APP_NAME}" ]]; then
  echo "ERROR: App binary missing at ${APP_SRC}" >&2
  exit 1
fi
echo "    App size: $(du -sh "${APP_SRC}" | awk '{print $1}')"

echo "==> Preparing stage…"
rm -f "${FINAL_DMG}"
mkdir -p "${STAGE}"

ditto --norsrc --noextattr "${APP_SRC}" "${STAGE}/${APP_NAME}.app"
xattr -cr "${STAGE}/${APP_NAME}.app" 2>/dev/null || true
find "${STAGE}/${APP_NAME}.app" -name '._*' -delete 2>/dev/null || true

bash "${ROOT}/Scripts/ensure_signing_identity.sh" >/dev/null 2>&1 || true
security unlock-keychain -p "${PINDOCK_KEYCHAIN_PASS:-pindock-local-sign}" "${KC_PATH}" 2>/dev/null || true
SIGN_HASH="$(security find-identity -v -p codesigning "${KC_PATH}" 2>/dev/null \
  | grep -F "\"${IDENTITY_NAME}\"" | head -1 | awk '{print $2}')"
if [[ -z "${SIGN_HASH}" ]]; then
  SIGN_HASH="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -F "\"${IDENTITY_NAME}\"" | head -1 | awk '{print $2}')"
fi
if [[ -n "${SIGN_HASH}" ]]; then
  echo "==> Re-signing app in clean stage…"
  CS=(--force --sign "${SIGN_HASH}" --identifier com.github.pindock.PinDock --timestamp=none)
  [[ -f "${KC_PATH}" ]] && CS+=(--keychain "${KC_PATH}")
  codesign "${CS[@]}" "${STAGE}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
  codesign "${CS[@]}" "${STAGE}/${APP_NAME}.app"
  codesign --verify --deep --strict "${STAGE}/${APP_NAME}.app"
fi

ln -sf /Applications "${STAGE}/Applications"

if [[ -f "${BG_SRC}" ]]; then
  mkdir -p "${STAGE}/.background"
  /bin/cp -X "${BG_SRC}" "${STAGE}/.background/background.png" 2>/dev/null \
    || cp "${BG_SRC}" "${STAGE}/.background/background.png"
  xattr -c "${STAGE}/.background/background.png" 2>/dev/null || true
fi

echo "==> Creating RW disk image…"
hdiutil create -size 40m -fs HFS+ -volname "${VOL_NAME}" -ov "${RW_DMG}" >/dev/null

echo "==> Mounting…"
MOUNT_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}")"
MOUNT="$(echo "${MOUNT_OUT}" | sed -n 's|.*\(/Volumes/.*\)|\1|p' | tail -1)"
if [[ -z "${MOUNT}" || ! -d "${MOUNT}" ]]; then
  MOUNT="/Volumes/${VOL_NAME}"
fi
echo "    Mounted: ${MOUNT}"

echo "==> Copying into volume…"
ditto --norsrc --noextattr "${STAGE}/${APP_NAME}.app" "${MOUNT}/${APP_NAME}.app"
ln -sf /Applications "${MOUNT}/Applications"
if [[ -d "${STAGE}/.background" ]]; then
  mkdir -p "${MOUNT}/.background"
  cp "${STAGE}/.background/background.png" "${MOUNT}/.background/background.png" 2>/dev/null || true
fi
xattr -cr "${MOUNT}/${APP_NAME}.app" 2>/dev/null || true

if [[ -d "${MOUNT}/.background" ]]; then
  SetFile -a V "${MOUNT}/.background" 2>/dev/null || chflags hidden "${MOUNT}/.background" 2>/dev/null || true
fi

if [[ -f "${DS_TEMPLATE}" ]]; then
  echo "==> Applying 1.0.1 Finder layout template…"
  cp "${DS_TEMPLATE}" "${MOUNT}/.DS_Store"
  SetFile -a V "${MOUNT}/.DS_Store" 2>/dev/null || true
fi

echo "==> Styling Finder window…"
osascript <<EOF || echo "Warning: Finder layout script failed"
tell application "Finder"
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set sidebar width of container window to 0
    set the bounds of container window to {200, 120, 840, 520}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 104
    set text size of opts to 12
    try
      set background picture of opts to file ".background:background.png"
    end try
    delay 0.6
    try
      set position of item "${APP_NAME}.app" of container window to {170, 210}
    end try
    try
      set position of item "Applications" of container window to {470, 210}
    end try
    update without registering applications
    delay 1.5
    close
    open
    delay 1.0
    close
  end tell
end tell
EOF

if [[ ! -f "${MOUNT}/.DS_Store" && -f "${DS_TEMPLATE}" ]]; then
  cp "${DS_TEMPLATE}" "${MOUNT}/.DS_Store"
fi
if [[ -f "${MOUNT}/.DS_Store" ]]; then
  echo "    .DS_Store present ($(wc -c < "${MOUNT}/.DS_Store") bytes)"
else
  echo "WARNING: no .DS_Store — layout may look random" >&2
fi

sync
sleep 2

echo "==> Unmounting…"
hdiutil detach "${MOUNT}" >/dev/null 2>&1 \
  || diskutil eject "${MOUNT}" >/dev/null 2>&1 \
  || hdiutil detach "${MOUNT}" -force >/dev/null 2>&1 \
  || true
MOUNT=""
sleep 1

echo "==> Compressing…"
rm -f "${FINAL_DMG}"
hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}" >/dev/null

if [[ -n "${SIGN_HASH:-}" ]]; then
  echo "==> Codesigning DMG…"
  codesign --force --sign "${SIGN_HASH}" --keychain "${KC_PATH}" --timestamp=none "${FINAL_DMG}" 2>/dev/null \
    || codesign --force --sign "${SIGN_HASH}" --timestamp=none "${FINAL_DMG}" 2>/dev/null \
    || true
fi

echo ""
echo "======== VERIFY ========"
VERIFY_OUT="$(hdiutil attach -readonly -nobrowse "${FINAL_DMG}" 2>&1)" || {
  echo "FAIL: could not mount ${FINAL_DMG}" >&2
  exit 1
}
VMOUNT="$(echo "${VERIFY_OUT}" | sed -n 's|.*\(/Volumes/.*\)|\1|p' | tail -1)"
ls -la "${VMOUNT}"
if [[ -d "${VMOUNT}/${APP_NAME}.app" && -L "${VMOUNT}/Applications" ]]; then
  echo "OK: app + Applications"
else
  echo "FAIL: missing contents" >&2
  hdiutil detach "${VMOUNT}" -force >/dev/null 2>&1 || true
  exit 1
fi
hdiutil detach "${VMOUNT}" >/dev/null 2>&1 || true
echo "DMG: ${FINAL_DMG} ($(du -sh "${FINAL_DMG}" | awk '{print $1}'))"
echo "========================"
echo ""
