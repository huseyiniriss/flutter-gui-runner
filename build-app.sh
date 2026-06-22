#!/usr/bin/env bash
# Builds FlutterRunner and bundles it into a menu-bar .app.
set -euo pipefail
cd "$(dirname "$0")"

echo "▶️  swift build…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/FlutterRunner"
APP="FlutterRunner.app"
echo "📦 bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FlutterRunner"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Flutter Runner</string>
  <key>CFBundleDisplayName</key><string>Flutter Runner</string>
  <key>CFBundleIdentifier</key><string>com.heyisoft.flutterrunner</string>
  <key>CFBundleExecutable</key><string>FlutterRunner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so the binary runs cleanly.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✅ Built $APP"
echo "   Run:     open ./$APP"
echo "   Install: cp -R ./$APP /Applications/"
