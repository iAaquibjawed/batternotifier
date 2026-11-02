#!/bin/bash
# Builds BatteryGuard.app and installs it to /Applications
set -euo pipefail
cd "$(dirname "$0")"
APP=build/BatteryGuard.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos13 Sources/main.swift -o build/bg-arm64
swiftc -O -target x86_64-apple-macos13 Sources/main.swift -o build/bg-x86
lipo -create build/bg-arm64 build/bg-x86 -output "$APP/Contents/MacOS/BatteryGuard"
rm build/bg-arm64 build/bg-x86
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>BatteryGuard</string>
  <key>CFBundleIdentifier</key><string>com.local.batteryguard</string>
  <key>CFBundleExecutable</key><string>BatteryGuard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
if [[ "${1:-}" == "install" ]]; then
  pkill -x BatteryGuard || true
  rm -rf /Applications/BatteryGuard.app
  cp -R "$APP" /Applications/
  open /Applications/BatteryGuard.app
  echo "Installed to /Applications and launched"
fi
if [[ "${1:-}" == "dmg" ]]; then
  STAGE=build/dmg && rm -rf "$STAGE" && mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f build/BatteryGuard.dmg
  hdiutil create -volname "BatteryGuard" -srcfolder "$STAGE" -ov -format UDZO build/BatteryGuard.dmg >/dev/null
  rm -rf "$STAGE"
  echo "Created build/BatteryGuard.dmg ($(du -h build/BatteryGuard.dmg | cut -f1))"
fi
