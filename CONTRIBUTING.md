# Contributing

Thanks for your interest! This is a small, focused macOS app — contributions are welcome.

## Dev setup

```sh
git clone https://github.com/huseyiniriss/flutter-gui-runner.git
cd flutter-gui-runner
swift build                 # debug build
./build-app.sh             # bundle FlutterRunner.app
open ./FlutterRunner.app
```

Requires Swift 6 (Xcode 16+). No third-party dependencies.

## Project layout

- `Sources/FlutterRunner/AppModel.swift` — all state + every shell/flutter/git call.
- `Sources/FlutterRunner/Theme.swift` — design tokens, button styles, `TabScaffold`, `Card`.
- `Sources/FlutterRunner/ContentView.swift` — Run tab + menu-bar panel + shared run controls.
- `Sources/FlutterRunner/Tabs.swift`, `Tabs2.swift` — the other tabs.
- `Sources/FlutterRunner/MainWindow.swift` — sidebar navigation shell.
- `scripts/` — icon, DMG, screenshots helpers.
- `docs/plans/` — phased roadmap.

## Conventions

- Match the surrounding style; keep comments meaningful, not noisy.
- All shell work goes through `AppModel` (login `zsh -lc`), never hardcode a path.
- UI spacing/colors/motion come from `Theme`, not inline literals.

## Releasing (maintainers)

Push a tag and CI builds the DMG and attaches it to the release:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

## Good first issues

- Notarization + Developer ID signing (so Gatekeeper stops warning).
- Deeper iOS signing (provisioning profiles, export options).
- A Linux/Windows port (the UI is macOS/SwiftUI today).
