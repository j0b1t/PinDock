#!/usr/bin/env bash
set -euo pipefail

# Build PinDock-*.zip and publish a GitHub Release.
# Usage:
#   ./Scripts/release.sh              # version from Info.plist
#   ./Scripts/release.sh 1.0.1        # override version
#   ./Scripts/release.sh --draft

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

DRAFT=0
VERSION_ARG=""
for a in "$@"; do
  case "$a" in
    --draft) DRAFT=1 ;;
    *) VERSION_ARG="$a" ;;
  esac
done

PLIST="${ROOT}/Resources/Info.plist"
if [[ -n "${VERSION_ARG}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION_ARG}" "${PLIST}"
  VERSION="${VERSION_ARG}"
else
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}" 2>/dev/null || echo "1.0.0")"
fi

TAG="v${VERSION}"
ZIP_NAME="PinDock-${VERSION}.zip"
ZIP_PATH="${ROOT}/${ZIP_NAME}"

echo "==> Version ${VERSION} (tag ${TAG})"
chmod +x Scripts/*.sh

echo "==> Building ZIP…"
./Scripts/package_zip.sh

if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "ERROR: expected ${ZIP_PATH}" >&2
  exit 1
fi

NOTES="$(cat <<EOF
## PinDock ${VERSION}

Open source — not Apple-notarized (no paid developer fee).

### Install
1. Download **${ZIP_NAME}**  
2. Double-click to unzip → **PinDock.app**  
3. Drag **PinDock.app** into **Applications**  
4. If macOS says **Not Opened** / **Move to Bin**:  
   **Right‑click → Open → Open**, or **System Settings → Privacy & Security → Open Anyway**  
5. **System Settings → Privacy & Security → Accessibility** → enable PinDock  

### Support
Lightning: \`j0b1t@strike.me\` · [Ko‑fi](https://ko-fi.com/j0b1t)

**SHA-256**
\`\`\`
$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')  ${ZIP_NAME}
\`\`\`
EOF
)"

echo "==> Publishing GitHub Release ${TAG}…"
ARGS=(release create "${TAG}" "${ZIP_PATH}" --title "PinDock ${VERSION}" --notes "${NOTES}")
if [[ "${DRAFT}" -eq 1 ]]; then
  ARGS+=(--draft)
else
  ARGS+=(--latest)
fi

if gh release view "${TAG}" >/dev/null 2>&1; then
  echo "    Release ${TAG} exists — uploading ZIP (clobber)…"
  gh release upload "${TAG}" "${ZIP_PATH}" --clobber
  gh release edit "${TAG}" --notes "${NOTES}" --latest 2>/dev/null || true
else
  gh "${ARGS[@]}"
fi

echo ""
echo "Done: https://github.com/j0b1t/PinDock/releases/tag/${TAG}"
echo "Latest: https://github.com/j0b1t/PinDock/releases/latest"
