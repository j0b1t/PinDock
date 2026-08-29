#!/usr/bin/env bash
set -euo pipefail

# Capture live v1.1 UI for README:
#   stills of the real menu-bar bubble (arrow + Dock / Settings)
#   still of the app window
#   walkthrough GIFs for both
#
# Usage: ./Scripts/capture_screenshots.sh
# Restores appLanguage / appColorScheme when done.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${PINDOCK_APP:-/Applications/PinDock.app}"
BIN="${APP}/Contents/MacOS/PinDock"
OUT="${ROOT}/docs/assets"
DOMAIN="com.github.pindock.PinDock"

if [[ ! -x "${BIN}" ]]; then
  echo "Missing ${BIN} — run ./Scripts/install.sh first" >&2
  exit 1
fi

mkdir -p "${OUT}"

saved_lang="$(defaults read "${DOMAIN}" appLanguage 2>/dev/null || true)"
saved_theme="$(defaults read "${DOMAIN}" appColorScheme 2>/dev/null || true)"

restore_prefs() {
  if [[ -n "${saved_lang}" ]]; then
    defaults write "${DOMAIN}" appLanguage "${saved_lang}"
  else
    defaults delete "${DOMAIN}" appLanguage 2>/dev/null || true
  fi
  if [[ -n "${saved_theme}" ]]; then
    defaults write "${DOMAIN}" appColorScheme "${saved_theme}"
  else
    defaults delete "${DOMAIN}" appColorScheme 2>/dev/null || true
  fi
}

defaults write "${DOMAIN}" appLanguage en
defaults write "${DOMAIN}" appColorScheme dark

pkill -x PinDock 2>/dev/null || true
sleep 0.4

TMP="$(mktemp -d /tmp/pindock-capture.XXXXXX)"
WINID_SWIFT="${TMP}/winid.swift"
WINID_BIN="${TMP}/winid"
cat > "${WINID_SWIFT}" << 'SWIFT'
import Cocoa
let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (id: Int, area: CGFloat)?
for info in infos {
    guard let name = info[kCGWindowOwnerName as String] as? String, name == "PinDock" else { continue }
    guard let num = info[kCGWindowNumber as String] as? Int else { continue }
    let b = info[kCGWindowBounds as String] as? [String: Any]
    let w = CGFloat((b?["Width"] as? NSNumber)?.doubleValue ?? 0)
    let h = CGFloat((b?["Height"] as? NSNumber)?.doubleValue ?? 0)
    if h < 80 || w < 80 { continue }
    let area = w * h
    if best == nil || area > best!.area { best = (num, area) }
}
if let best { print(best.id) }
SWIFT

echo "==> Compiling capture helpers…"
xcrun swiftc -O "${WINID_SWIFT}" -o "${WINID_BIN}"

trap 'rm -rf "${TMP}"; restore_prefs' EXIT

window_id() { "${WINID_BIN}"; }

frontmost() {
  osascript >/dev/null 2>&1 <<'OSA' || true
tell application "System Events"
  set frontmost of process "PinDock" to true
end tell
OSA
}

LAUNCH_PID=""
launch_wait() {
  local flag="$1"
  pkill -x PinDock 2>/dev/null || true
  sleep 0.35
  "${BIN}" ${flag} -AppleLanguages "(en)" >/dev/null 2>&1 &
  LAUNCH_PID=$!
  local id=""
  for _ in {1..48}; do
    sleep 0.25
    id="$(window_id || true)"
    if [[ -n "${id}" ]]; then
      return 0
    fi
  done
  echo "ERROR: PinDock window not found for ${flag}" >&2
  pkill -x PinDock 2>/dev/null || true
  exit 1
}

capture_still() {
  local flag="$1"
  local dest="$2"
  launch_wait "${flag}"
  frontmost
  sleep 1.5
  local id
  id="$(window_id || true)"
  if [[ -z "${id}" ]]; then
    echo "ERROR: window gone before still (${flag})" >&2
    pkill -x PinDock 2>/dev/null || true
    exit 1
  fi
  screencapture -l"${id}" "${dest}"
  echo "Wrote ${dest} ($(sips -g pixelWidth -g pixelHeight "${dest}" 2>/dev/null | awk '/pixel/{printf $2" "}'))"
  kill "${LAUNCH_PID}" 2>/dev/null || pkill -x PinDock 2>/dev/null || true
  wait "${LAUNCH_PID}" 2>/dev/null || true
  sleep 0.3
}

capture_gif() {
  local flag="$1"
  local dest="$2"
  local seconds="$3"
  local max_width="$4"
  local frames="${TMP}/frames-$(basename "${dest}" .gif)"
  rm -rf "${frames}"
  mkdir -p "${frames}"
  launch_wait "${flag}"
  frontmost
  sleep 0.5
  local fps=8
  local total
  total="$(python3 -c "print(int(${seconds} * ${fps}))")"
  local i
  for i in $(seq 0 $((total - 1))); do
    local id
    id="$(window_id || true)"
    if [[ -n "${id}" ]]; then
      printf -v name "%s/frame-%04d.png" "${frames}" "${i}"
      screencapture -x -l"${id}" "${name}" || true
    fi
  done
  python3 "${ROOT}/Scripts/make_gif.py" "${frames}" "${dest}" "${max_width}" 100 256
  kill "${LAUNCH_PID}" 2>/dev/null || pkill -x PinDock 2>/dev/null || true
  wait "${LAUNCH_PID}" 2>/dev/null || true
  sleep 0.3
}

echo "==> Stills dark (real menu-bar bubble + arrow, app window)"
defaults write "${DOMAIN}" appColorScheme dark
capture_still "--ui-preview-popover" "${OUT}/screenshot-popover.png"
capture_still "--ui-preview-popover-settings" "${OUT}/screenshot-settings.png"
capture_still "--ui-preview-window" "${OUT}/screenshot-window.png"
cp "${OUT}/screenshot-popover.png" "${OUT}/screenshot-popover-dark.png"
cp "${OUT}/screenshot-settings.png" "${OUT}/screenshot-settings-dark.png"
cp "${OUT}/screenshot-window.png" "${OUT}/screenshot-window-dark.png"
cp "${OUT}/screenshot-settings.png" "${OUT}/screenshot-menubar.png"

echo "==> Stills light"
defaults write "${DOMAIN}" appColorScheme light
capture_still "--ui-preview-popover" "${OUT}/screenshot-popover-light.png"
capture_still "--ui-preview-popover-settings" "${OUT}/screenshot-settings-light.png"
capture_still "--ui-preview-window" "${OUT}/screenshot-window-light.png"

echo "==> Walkthrough GIFs (dark, 2× README display size)"
defaults write "${DOMAIN}" appColorScheme dark
capture_gif "--ui-demo-menubar" "${OUT}/walkthrough-menubar.gif" 8.5 900
capture_gif "--ui-demo-window" "${OUT}/walkthrough-window.gif" 7.5 1600

echo "Done."
