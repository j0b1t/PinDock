#!/usr/bin/env bash
set -euo pipefail

# Capture live v1.1 UI for README: Dock tab, Settings tab, app window.
# Usage: ./Scripts/capture_screenshots.sh
# Restores appLanguage / appColorScheme when done.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${PINDOCK_APP:-/Applications/PinDock.app}"
BIN="${APP}/Contents/MacOS/PinDock"
BUNDLE_ID="com.github.pindock.PinDock"
OUT="${ROOT}/docs/assets"
DOMAIN="$BUNDLE_ID"

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
trap restore_prefs EXIT

defaults write "${DOMAIN}" appLanguage en
defaults write "${DOMAIN}" appColorScheme dark

pkill -x PinDock 2>/dev/null || true
sleep 0.4

WINID_SWIFT="$(mktemp /tmp/pindock-winid.XXXXXX.swift)"
WINID_BIN="$(mktemp /tmp/pindock-winid.XXXXXX)"
rm -f "${WINID_BIN}"
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
xcrun swiftc -O "${WINID_SWIFT}" -o "${WINID_BIN}"
trap 'rm -f "${WINID_SWIFT}" "${WINID_BIN}"; restore_prefs' EXIT

window_id() {
  "${WINID_BIN}"
}

capture() {
  local flag="$1"
  local dest="$2"
  pkill -x PinDock 2>/dev/null || true
  sleep 0.3
  "${BIN}" ${flag} -AppleLanguages "(en)" >/dev/null 2>&1 &
  local pid=$!
  local id=""
  for _ in {1..40}; do
    sleep 0.25
    id="$(window_id || true)"
    if [[ -n "${id}" ]]; then break; fi
  done
  if [[ -z "${id}" ]]; then
    echo "ERROR: PinDock window not found for ${flag}" >&2
    pkill -x PinDock 2>/dev/null || true
    exit 1
  fi
  # Let glass / SwiftUI layout settle.
  sleep 0.8
  # Shadow on, no UI beep. Tight window capture at retina scale.
  screencapture -l"${id}" "${dest}"
  echo "Wrote ${dest} ($(sips -g pixelWidth -g pixelHeight "${dest}" 2>/dev/null | awk '/pixel/{printf $2" "}'))"
  kill "${pid}" 2>/dev/null || pkill -x PinDock 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  sleep 0.3
}

echo "==> Capturing README screenshots from ${APP}"
capture "--ui-preview" "${OUT}/screenshot-popover.png"
capture "--ui-preview-settings" "${OUT}/screenshot-settings.png"
capture "--ui-preview-window" "${OUT}/screenshot-window.png"

# Keep the old filename so existing links still show current UI (Settings tab).
cp "${OUT}/screenshot-settings.png" "${OUT}/screenshot-menubar.png"

echo "Done."
