<div align="center">

<img src="assets/logo-256.png" width="128" height="128" alt="Flutter GUI Runner logo" />

# Flutter GUI Runner

**A native macOS control panel for Flutter — for developers (and AI agents) who code in editors without a Flutter plugin.**

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)]()
[![Built with](https://img.shields.io/badge/built%20with-SwiftUI-orange)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

</div>

---

## Why this exists

If you write Flutter in **Zed, Neovim, Helix, Sublime, or a plain terminal**, you
get great LSP autocomplete — but none of the run/device/build UI that Android
Studio and VS Code bake in. You're stuck memorizing `flutter` flags and copying
device IDs by hand.

This is especially painful in **agentic coding** workflows. When an AI agent
(Claude Code, Cursor, Windsurf, Aider, …) is editing your Flutter project, *you*
still need to drive the device side: pick a target, run, hot reload, build an
AAB/IPA, manage signing. **Flutter GUI Runner is that side of the loop** — a
small always-available app that does everything Android Studio's Flutter plugin
does, next to whatever editor (or agent) you use.

> Zed/editor extensions can't draw this UI (no toolbar buttons, no device
> dropdowns). A standalone app can — so that's what this is.

## Features

- 🐦 **Menu-bar quick panel** — pick device, Run/Stop, Hot reload/restart, quick build & tools, live log. Never leave your editor.
- 🪟 **Full window** with tabs:
  - **Run** — device picker + debug/profile/release + hot reload/restart (reliable, via `--pid-file` + `SIGUSR1/2`)
  - **Emulators** — list & launch Android AVDs and iOS simulators
  - **Build** — APK / **AAB** / **IPA** / iOS / Web / macOS with flavor, build name/number, `--dart-define`, `--split-per-abi`, `--obfuscate`; prefilled from `pubspec.yaml`; **reveal artifact in Finder**
  - **Packages** — view `pubspec` deps, add / remove / **upgrade** a package, `pub outdated`
  - **Commands** — `pub get/upgrade/outdated`, `analyze`, `test`, `format`, `build_runner`, `gen-l10n`, `clean`
  - **SDK** — current Flutter/Dart version & channel, **upgrade**, switch channel
  - **Doctor** — `flutter doctor -v`
  - **Settings** — Flutter path override, projects scan root, **FVM** toggle, UI size
- 🔐 **Android signing** — choose/generate a keystore (`keytool`), view it, write `android/key.properties`
- 📺 **Resizable terminal** — drag the divider; font scales with the UI; everything **persists per project** across restarts
- ⚙️ **FVM-aware** — uses `fvm flutter` automatically when a project pins a version
- 🧩 **Editor-agnostic & zero lock-in** — runs the exact same `flutter` commands a terminal would (login shell), so behavior matches your CLI

## Install

> ⚠️ The app is **not notarized yet** (open-source, unsigned builds). macOS
> Gatekeeper will warn on first launch.

1. Download `FlutterGUIRunner.dmg` from [Releases](../../releases).
2. Drag **Flutter Runner** into `Applications`.
3. First launch: **right-click the app → Open → Open** (only needed once).

Requires a working **Flutter SDK** on your `PATH` (or set the path in Settings).

## Build from source

```sh
git clone https://github.com/<owner>/flutter-gui-runner.git
cd flutter-gui-runner
./build-app.sh          # builds FlutterRunner.app
open ./FlutterRunner.app
# package a DMG:
./scripts/make-dmg.sh
```

Needs Swift 6 (Xcode 16+). No third-party dependencies.

## How it works

- Every command runs through a **login `zsh -lc`** in the project directory, so
  `PATH` and the iOS/Android toolchains resolve exactly like your terminal.
- `flutter run` is launched with `--pid-file`; **hot reload/restart** are sent as
  `SIGUSR1` / `SIGUSR2` — reliable without a TTY.
- Log output is **coalesced and rendered in an `NSTextView`** so a chatty
  `flutter run` stays smooth.
- No telemetry. No network calls except what `flutter` itself does.

## Roadmap

See [`docs/plans`](docs/plans). Next up: Developer-ID signing + notarization,
deeper iOS signing, multi-device run, auto-update.

## Contributing

Issues and PRs welcome — this is an open-source project. Good first areas:
notarization/CI, iOS signing, Linux/Windows port (the GUI is macOS/SwiftUI today).

## License

[MIT](LICENSE) © huseyiniriss
