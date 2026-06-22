#!/usr/bin/env bash
# Capture screenshots of each FlutterRunner window for the README.
# (Programmatic capture needs Screen Recording permission, so this is a manual
#  helper: switch to a tab, press Enter, it grabs the window.)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/screenshots
open ./FlutterRunner.app || true

shots=(run emulators build packages commands sdk)
for name in "${shots[@]}"; do
  read -rp "Switch to the '$name' tab, then press Enter to capture… "
  osascript -e 'tell application "System Events" to set frontmost of (first process whose bundle identifier is "com.heyisoft.flutterrunner") to true' 2>/dev/null || true
  sleep 0.4
  WID="$(swift scripts/window-id.swift 2>/dev/null || true)"
  if [ -n "${WID:-}" ]; then
    screencapture -l"$WID" -o "assets/screenshots/$name.png"
    echo "  → assets/screenshots/$name.png"
  else
    echo "  (window not found — grant Screen Recording permission to Terminal)"
  fi
done
echo "Done. Reference them in README.md."
