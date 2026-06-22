# Phase 02 — Devices & Emulators

## Goal
See and control every target: running devices, Android AVDs, iOS simulators.

## Tasks
- [x] List emulators by parsing `flutter emulators` (the `--machine` flag is
      empty in current Flutter, so parse the `id • name • manufacturer • platform`
      table).
- [x] Launch an emulator: `flutter emulators --launch <id>`.
- [ ] Create AVD: `flutter emulators --create [--name <x>]`.
- [ ] iOS simulators in detail via `xcrun simctl list devices available --json`;
      boot (`simctl boot <udid>` + `open -a Simulator`) and shutdown.
- [ ] Cold boot / wipe data for Android AVDs (`emulator -avd <x> -wipe-data`).
- [ ] Auto-refresh device list after launching an emulator.

## Data
- `Emulator { id, name, manufacturer, platform }`.
- Platform → SF Symbol + “Android/iOS” badge.
