# Phase 07 — Polish & distribution

## Polish
- Custom app icon (Flutter-blue, distinctive — not default).
- Settings: flutter/fvm path override, projects scan root, theme, launch-at-login.
- Better log view: ANSI color, per-task tabs, search, copy.
- Empty/error states (no SDK, no devices, build failure with parsed errors).
- Localization (TR/EN) — matches the developer's stack.

## Distribution
- Decide naming (current `FlutterRunner` collides with a pub.dev package + Flutter
  iOS "Runner" target → rename candidate: Hearth / Embr / FlutterDeck).
- Code signing + **notarization** (`codesign --options runtime` + `notarytool`)
  so users don't hit Gatekeeper; otherwise document right-click → Open.
- Package `.dmg` (create-dmg).
- GitHub Actions: build, sign, notarize, attach `.dmg` to a release on tag.
- README with GIF, screenshots, Zed-first positioning; LICENSE (MIT).
