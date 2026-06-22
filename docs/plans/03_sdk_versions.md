# Phase 03 — SDK & version management

## Goal
See and manage the Flutter SDK from the UI.

## Tasks
- [x] Show current version + channel + Dart version (`flutter --version`).
- [x] Upgrade SDK (`flutter upgrade`).
- [x] Switch channel (`flutter channel <stable|beta|master>`).
- [x] Run `flutter doctor -v` in a dedicated tab.
- [ ] FVM: detect `.fvmrc`, list installed versions (`fvm list`), switch
      project version (`fvm use <v>`), install (`fvm install <v>`).
- [ ] Show "update available" badge by diffing local vs `flutter upgrade --dry-run`.

## Notes
- Upgrade/channel are slow + network-bound → stream output, disable buttons
  while running.
