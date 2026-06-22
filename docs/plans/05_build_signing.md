# Phase 05 — Build & Signing

## Build
- Artifacts: APK, AAB, IPA, iOS (no codesign), Web, macOS.
- Options UI: mode (debug/profile/release), `--flavor`, `--build-name`,
  `--build-number`, `--dart-define(-from-file)`, `--split-per-abi`, `--obfuscate
  --split-debug-info=<dir>`, `--target lib/main_x.dart`.
- After build: reveal artifact in Finder (parse output path).

## Android signing
- Generate keystore via `keytool -genkeypair -v -keystore <x>.jks -keyalg RSA
  -keysize 2048 -validity 10000 -alias <alias>` (form: alias, passwords, dname).
- Write/update `android/key.properties` and wire `build.gradle` (guided).
- Show **SHA-1 / SHA-256** (`keytool -list -v -keystore <x>`) — for Firebase /
  Google sign-in. Copy to clipboard.

## iOS signing
- List identities: `security find-identity -p codesigning -v`.
- Show provisioning profiles; open Xcode signing settings.
- `ExportOptions.plist` helper for `build ipa --export-options-plist`.

## Security
- Never store keystore passwords in plaintext config we own; write only into the
  user's `key.properties` (gitignored) and warn about it.
