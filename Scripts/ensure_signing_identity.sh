#!/usr/bin/env bash
set -euo pipefail

# Stable local code-signing identity so Accessibility survives updates.
# Uses a *dedicated* keychain (not login) with a known password so codesign
# never pops the macOS Keychain password dialog.

IDENTITY_NAME="${PINDOCK_IDENTITY_NAME:-PinDock Development}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_DIR="${SCRIPT_DIR}/certs"
P12_PATH="${CERT_DIR}/PinDockDevelopment.p12"
CER_PATH="${CERT_DIR}/PinDockDevelopment.cer"
P12_PASS="pindock"
# Fixed password for the dedicated keychain only (not your login password).
KC_PASS="${PINDOCK_KEYCHAIN_PASS:-pindock-local-sign}"
# Absolute path required — relative paths break unlock/codesign.
KC_PATH="${CERT_DIR}/PinDock.keychain-db"
KC_PATH_FILE="${CERT_DIR}/.keychain-path"

mkdir -p "${CERT_DIR}"

# ── Dedicated keychain (no interaction with login keychain password) ────────
create_or_unlock_keychain() {
  if [[ ! -f "${KC_PATH}" ]]; then
    echo "==> Creating dedicated signing keychain (one-time)…"
    security create-keychain -p "${KC_PASS}" "${KC_PATH}"
  fi
  # Stay unlocked for 6h so install/package don't re-prompt mid-session.
  security set-keychain-settings -lut 21600 "${KC_PATH}" 2>/dev/null || true
  if ! security unlock-keychain -p "${KC_PASS}" "${KC_PATH}" 2>/dev/null; then
    echo "==> Recreating signing keychain (old password mismatch)…"
    security delete-keychain "${KC_PATH}" 2>/dev/null || true
    rm -f "${KC_PATH}"
    security create-keychain -p "${KC_PASS}" "${KC_PATH}"
    security set-keychain-settings -lut 21600 "${KC_PATH}" 2>/dev/null || true
    security unlock-keychain -p "${KC_PASS}" "${KC_PATH}"
  fi

  # Put it first in the search list so find-identity / codesign see it.
  # Keep existing user keychains.
  local current
  current="$(security list-keychains -d user 2>/dev/null | sed 's/"//g' | tr '\n' ' ' || true)"
  if ! echo " ${current} " | grep -q " ${KC_PATH} "; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s "${KC_PATH}" ${current}
  fi
}

allow_codesign_without_prompt() {
  # Critical: without this, every codesign asks for Keychain password.
  security set-key-partition-list \
    -S "apple-tool:,apple:,codesign:" \
    -s \
    -k "${KC_PASS}" \
    "${KC_PATH}" >/dev/null 2>&1 || true
}

identity_ok() {
  security find-identity -v -p codesigning "${KC_PATH}" 2>/dev/null \
    | grep -F "\"${IDENTITY_NAME}\"" >/dev/null
}

create_or_unlock_keychain

if identity_ok; then
  allow_codesign_without_prompt
  echo "${KC_PATH}" > "${KC_PATH_FILE}"
  echo "Signing identity OK: ${IDENTITY_NAME}"
  echo "  Keychain: ${KC_PATH} (no login-password prompts)"
  exit 0
fi

# ── Generate self-signed codesign cert once ─────────────────────────────────
TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

if [[ ! -f "${P12_PATH}" ]]; then
  echo "==> Generating ${IDENTITY_NAME} certificate (one-time)…"
  cat > "${TMP}/ext.cnf" <<'EOF'
[ v3_codesign ]
basicConstraints = critical,CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  openssl genrsa -out "${TMP}/key.pem" 2048 2>/dev/null
  openssl req -new -key "${TMP}/key.pem" -out "${TMP}/csr.pem" \
    -subj "/CN=${IDENTITY_NAME}/O=PinDock/C=DE" 2>/dev/null
  openssl x509 -req -days 3650 \
    -in "${TMP}/csr.pem" -signkey "${TMP}/key.pem" -out "${TMP}/cert.pem" \
    -extfile "${TMP}/ext.cnf" -extensions v3_codesign 2>/dev/null
  openssl pkcs12 -export \
    -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
    -out "${P12_PATH}" -passout "pass:${P12_PASS}" \
    -name "${IDENTITY_NAME}" 2>/dev/null
  cp "${TMP}/cert.pem" "${CER_PATH}"
fi

if [[ ! -f "${CER_PATH}" && -f "${P12_PATH}" ]]; then
  openssl pkcs12 -in "${P12_PATH}" -passin "pass:${P12_PASS}" -clcerts -nokeys \
    -out "${CER_PATH}" 2>/dev/null || true
fi

echo "==> Importing identity into dedicated keychain…"
security import "${P12_PATH}" \
  -k "${KC_PATH}" \
  -P "${P12_PASS}" \
  -A \
  -T /usr/bin/codesign \
  -T /usr/bin/security 2>/dev/null \
  || security import "${P12_PATH}" -k "${KC_PATH}" -P "${P12_PASS}" -A 2>/dev/null || true

if [[ -f "${CER_PATH}" ]]; then
  security add-trusted-cert -d -r trustRoot -p codeSign \
    -k "${KC_PATH}" "${CER_PATH}" 2>/dev/null || true
fi

allow_codesign_without_prompt
echo "${KC_PATH}" > "${KC_PATH_FILE}"

if identity_ok; then
  echo "Signing identity ready: ${IDENTITY_NAME}"
  security find-identity -v -p codesigning "${KC_PATH}" | grep -F "${IDENTITY_NAME}" || true
  exit 0
fi

echo "WARNING: Could not register codesigning identity." >&2
exit 1
