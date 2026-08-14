#!/usr/bin/env bash
set -euo pipefail

# Build PinDock.app with a stable local code signature.
# Staging under /tmp (not iCloud) avoids resource-fork codesign failures.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PinDock"
EXEC_NAME="PinDock"
BUNDLE_ID="com.github.pindock.PinDock"
IDENTITY_NAME="${PINDOCK_IDENTITY_NAME:-PinDock Development}"

STAGE="$(mktemp -d "/tmp/pindock-pkg.XXXXXX")"
cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT

export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

cd "${ROOT}"
chmod +x Scripts/ensure_signing_identity.sh 2>/dev/null || true

echo "==> Building release binary…"
swift build -c release --product "${EXEC_NAME}"

BIN="$(swift build -c release --show-bin-path)/${EXEC_NAME}"
if [[ ! -x "${BIN}" ]]; then
  echo "Binary not found: ${BIN}" >&2
  exit 1
fi

CLEAN_BIN="${STAGE}/${EXEC_NAME}"
/bin/cp -X "${BIN}" "${CLEAN_BIN}" 2>/dev/null || {
  /bin/cp "${BIN}" "${CLEAN_BIN}"
  xattr -c "${CLEAN_BIN}" 2>/dev/null || true
}
chmod +x "${CLEAN_BIN}"

APP_PATH="${STAGE}/${APP_NAME}.app"
echo "==> Creating app bundle in ${STAGE}…"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"

/bin/cp -X "${CLEAN_BIN}" "${APP_PATH}/Contents/MacOS/${EXEC_NAME}" 2>/dev/null \
  || /bin/cp "${CLEAN_BIN}" "${APP_PATH}/Contents/MacOS/${EXEC_NAME}"
chmod +x "${APP_PATH}/Contents/MacOS/${EXEC_NAME}"

/bin/cp -X "${ROOT}/Resources/Info.plist" "${APP_PATH}/Contents/Info.plist" 2>/dev/null \
  || /bin/cp "${ROOT}/Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"
printf 'APPL????' > "${APP_PATH}/Contents/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" \
  "${APP_PATH}/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${BUNDLE_ID}" \
    "${APP_PATH}/Contents/Info.plist"

if [[ -f "${ROOT}/Resources/AppIcon.icns" ]]; then
  /bin/cp -X "${ROOT}/Resources/AppIcon.icns" "${APP_PATH}/Contents/Resources/AppIcon.icns" 2>/dev/null \
    || /bin/cp "${ROOT}/Resources/AppIcon.icns" "${APP_PATH}/Contents/Resources/AppIcon.icns"
  xattr -c "${APP_PATH}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" \
    "${APP_PATH}/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
      "${APP_PATH}/Contents/Info.plist"
fi

xattr -cr "${APP_PATH}" 2>/dev/null || true
find "${APP_PATH}" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true

echo "==> Signing…"
SIGN_OK=0
KC_PATH="$(cd "${ROOT}/Scripts/certs" && pwd)/PinDock.keychain-db"
bash "${ROOT}/Scripts/ensure_signing_identity.sh" || true
security unlock-keychain -p "${PINDOCK_KEYCHAIN_PASS:-pindock-local-sign}" "${KC_PATH}" 2>/dev/null || true

SIGN_HASH="$(security find-identity -v -p codesigning "${KC_PATH}" 2>/dev/null \
  | grep -F "\"${IDENTITY_NAME}\"" | head -1 | awk '{print $2}')"
if [[ -z "${SIGN_HASH}" ]]; then
  SIGN_HASH="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -F "\"${IDENTITY_NAME}\"" | head -1 | awk '{print $2}')"
fi

if [[ -n "${SIGN_HASH}" ]]; then
  echo "    Identity: ${IDENTITY_NAME} (${SIGN_HASH})"
  CS=(--force --sign "${SIGN_HASH}" --identifier "${BUNDLE_ID}" --timestamp=none)
  [[ -f "${KC_PATH}" ]] && CS+=(--keychain "${KC_PATH}")
  codesign "${CS[@]}" "${APP_PATH}/Contents/MacOS/${EXEC_NAME}"
  codesign "${CS[@]}" "${APP_PATH}"
  codesign --verify --deep --strict "${APP_PATH}" 2>/dev/null && SIGN_OK=1
fi

if [[ "${SIGN_OK}" -ne 1 ]]; then
  echo "WARNING: falling back to ad-hoc sign" >&2
  codesign --force --deep --sign - --identifier "${BUNDLE_ID}" \
    "${APP_PATH}/Contents/MacOS/${EXEC_NAME}"
  codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${APP_PATH}"
fi

echo "    $(codesign -dvv "${APP_PATH}" 2>&1 | grep -E 'Identifier|Authority|Signature=' | tr '\n' ' ')"

OUT_APP="${ROOT}/${APP_NAME}.app"
rm -rf "${OUT_APP}"
ditto --norsrc --noextattr "${APP_PATH}" "${OUT_APP}"
xattr -cr "${OUT_APP}" 2>/dev/null || true
find "${OUT_APP}" -name '._*' -delete 2>/dev/null || true
if [[ "${SIGN_OK}" -eq 1 && -n "${SIGN_HASH}" ]]; then
  CS=(--force --sign "${SIGN_HASH}" --identifier "${BUNDLE_ID}" --timestamp=none)
  [[ -f "${KC_PATH}" ]] && CS+=(--keychain "${KC_PATH}")
  codesign "${CS[@]}" "${OUT_APP}/Contents/MacOS/${EXEC_NAME}" 2>/dev/null || true
  codesign "${CS[@]}" "${OUT_APP}" 2>/dev/null || true
fi

if [[ ! -x "${OUT_APP}/Contents/MacOS/${EXEC_NAME}" ]]; then
  echo "ERROR: app binary missing after package" >&2
  exit 1
fi

echo ""
echo "Done: ${OUT_APP}"
du -sh "${OUT_APP}"
echo ""
