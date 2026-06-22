# Phase 01 — App shell

## Goal
Turn the menu-bar-only MVP into a real app: a main window with tabs, plus the
menu-bar quick panel, both backed by one shared `AppModel`.

## Tasks
- [x] Add `WindowGroup` main window alongside `MenuBarExtra`.
- [x] `MainWindow` with `TabView`: Run · Emulators · SDK · Commands · Doctor.
- [x] Make it a normal app (Dock icon + window); keep menu-bar icon for quick run.
- [x] Centralize shell execution in `AppModel` (`runCapture`, `launchStreaming`).
- [ ] Extract a dedicated `CommandRunner` type (refactor, later).

## Notes
- Run tab reuses the existing compact `ContentView` (self-contained).
- `LSUIElement` removed so the window shows and there is a Dock presence.
