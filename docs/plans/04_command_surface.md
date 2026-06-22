# Phase 04 — Full command surface

## Goal
Every routine flutter/dart command as a one-click action, with output.

## Commands
- pub: `get`, `upgrade`, `upgrade --major-versions`, `outdated`, `add <pkg>`,
  `remove <pkg>`, `cache repair`
- quality: `analyze`, `test`, `test <file>`, `format .`
- codegen: `dart run build_runner build/watch --delete-conflicting-outputs`
- l10n: `gen-l10n`
- maintenance: `clean`, `pub get` combo
- scaffolding: `flutter create` (new project / add platforms)

## Design
- A `Command` model: `{ title, args, needsInput?, destructive? }`.
- Grouped sections in the Commands tab.
- `pub add`/`remove` prompt for a package name (later: pub.dev search → Phase 06).
