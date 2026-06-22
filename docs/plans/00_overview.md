# FlutterRunner — Product Roadmap (Overview)

## Vision
A standalone macOS app that lets you manage the **entire** Flutter workflow
without Android Studio / VS Code — for editor-agnostic developers (Zed, Helix,
Sublime, terminal). Run, debug, hot reload, manage emulators/simulators, the
Flutter SDK, signing keys, dependencies, and builds — all from one UI.

## Why
Zed (and other LSP-only editors) cannot provide a Flutter run/device UI via
extensions. The CLI works but is tedious. No GUI tool covers run + emulator +
SDK + signing + build in one place. This is the gap.

## Form factor
- **Main window** with tabs (full control surface).
- **Menu-bar icon** for quick run / hot reload while coding.
- Both share one `AppModel`.

## Architecture principles
- All shell work goes through one `CommandRunner` (login `zsh -lc`, so PATH and
  the iOS/Android toolchains resolve exactly like a terminal).
- FVM-aware: prefer project `fvm flutter` when present, else global.
- Streaming output into a log view; long-running `flutter run` uses `--pid-file`
  + `SIGUSR1`/`SIGUSR2` for hot reload/restart.
- No secrets hardcoded; flutter path resolved at runtime.

## Phases
| # | Phase | Delivers |
|---|-------|----------|
| 01 | App shell | Windowed TabView + menu bar, shared model, command runner |
| 02 | Devices & Emulators | List/launch Android AVDs + iOS simulators, create AVD |
| 03 | SDK & versions | Current version/channel, upgrade, channel switch, FVM, doctor |
| 04 | Command surface | pub get/upgrade/add/remove/outdated, clean, analyze, test, format, gen-l10n, build_runner, create |
| 05 | Build & Signing | Build options (flavor, name/number, split, obfuscate); Android keystore gen + key.properties + SHA; iOS signing info |
| 06 | Dependencies & projects | pubspec view, pub.dev search add/remove, multi-project, recents |
| 07 | Polish & distribution | Custom icon, settings, notarization, DMG, GitHub Actions release |

## Status
- Phase 00 (MVP): ✅ run / hot reload / restart / stop / build / basic tools.
- Phase 01–03: in progress.
