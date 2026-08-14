#!/usr/bin/env bash
set -euo pipefail

# Install / update PinDock at a FIXED path with a STABLE signature.
# That is what makes Accessibility survive updates.
#
# First time:
#   ./Scripts/install.sh
#   System Settings → Privacy & Security → Accessibility → enable PinDock
#     (only the copy under /Applications)
#
# Later updates:
#   ./Scripts/install.sh
#   Do NOT remove PinDock from Accessibility — just overwrite the app.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PinDock"
DEST="/Applications/${APP_NAME}.app"
BUNDLE_ID="com.github.pindock.PinDock"
IDENTITY_NAME="${PINDOCK_IDENTITY_NAME:-PinDock Development}"

cd "${ROOT}"
chmod +x Scripts/package_app.sh Scripts/ensure_signing_identity.sh

echo "==> Building…"
./Scripts/package_app.sh

SRC="${ROOT}/${APP_NAME}.app"
if [[ ! -d "${SRC}" ]]; then
  echo "Missing ${SRC}" >&2
  exit 1
fi

if pgrep -x PinDock >/dev/null 2>&1; then
  echo "==> Quitting running PinDock…"
  pkill -x PinDock 2>/dev/null || true
  sleep 0.6
fi

echo "==> Ensuring signing identity…"
bash Scripts/ensure_signing_identity.sh

KC_PATH="$(cd "${ROOT}/Scripts/certs" && pwd)/PinDock.keychain-db"
security unlock-keychain -p "${PINDOCK_KEYCHAIN_PASS:-pindock-local-sign}" "${KC_PATH}" 2>/dev/null || true
SIGN_HASH="$(security find-identity -v -p codesigning "${KC_PATH}" 2>/dev/null \
  | grep -F "\"${IDENTITY_NAME}\"" | head -1 | awk '{print $2}')"
if [[ -z "${SIGN_HASH}" ]]; then
  SIGN_HASH="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -F "\"${IDENTITY_NAME}\"" | head -1 | awk '{print $2}')"
fi
if [[ -z "${SIGN_HASH}" ]]; then
  echo "ERROR: No stable signing identity. Accessibility will break on every update." >&2
  echo "Fix: run Scripts/ensure_signing_identity.sh" >&2
  exit 1
fi

echo "==> Installing to ${DEST} (in-place overwrite, keeps TCC)…"
export COPYFILE_DISABLE=1
xattr -cr "${SRC}" 2>/dev/null || true

# IMPORTANT: do NOT rm -rf the destination first — overwrite in place so
# macOS keeps the same app identity for Accessibility when possible.
mkdir -p "${DEST}"
ditto "${SRC}" "${DEST}"
xattr -cr "${DEST}" 2>/dev/null || true
find "${DEST}" -name '._*' -delete 2>/dev/null || true

echo "==> Signing ${DEST} with ${SIGN_HASH} (dedicated keychain, no password prompt)…"
CODESIGN_ARGS=(
  --force --deep
  --sign "${SIGN_HASH}"
  --identifier "${BUNDLE_ID}"
  --timestamp=none
)
if [[ -f "${KC_PATH}" ]]; then
  CODESIGN_ARGS+=(--keychain "${KC_PATH}")
fi
codesign "${CODESIGN_ARGS[@]}" "${DEST}"

echo ""
echo "Installed: ${DEST}"
codesign -dvv "${DEST}" 2>&1 | grep -E 'Identifier|Authority|Format' || true
echo "Requirement:"
codesign -d -r- "${DEST}" 2>&1 | grep designated || true
echo ""
echo "Always open THIS copy:"
echo "  open ${DEST}"
echo ""
echo "First time only → Accessibility → enable PinDock (from /Applications)."
echo "Updates: run this script again; do not remove the Accessibility entry."
echo ""
open "${DEST}"
