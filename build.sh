#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/build/Warp Voice.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -target "$arch-apple-macos13.0" -O Sources/HoldKey.swift Sources/main.swift -o "build/WarpVoice-$arch" -framework AppKit -framework AVFoundation -framework ApplicationServices -framework UserNotifications
done
lipo -create build/WarpVoice-arm64 build/WarpVoice-x86_64 -output "$app/Contents/MacOS/WarpVoice"
cp Sources/transcribe.py "$app/Contents/Resources/transcribe.py"
cp Sources/updater.py "$app/Contents/Resources/updater.py"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Warp Voice</string>
<key>CFBundleIdentifier</key><string>local.dov.warpvoice</string>
<key>CFBundleExecutable</key><string>WarpVoice</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Запись голоса для диктовки через Warp.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
echo "Built: $app"
