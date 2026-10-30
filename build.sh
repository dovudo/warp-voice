#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/build/Warp Voice.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -swift-version 5 -O Sources/HoldKey.swift Sources/main.swift -o "$app/Contents/MacOS/WarpVoice" -framework AppKit -framework AVFoundation -framework ApplicationServices -framework UserNotifications
cp Sources/transcribe.py "$app/Contents/Resources/transcribe.py"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Warp Voice</string>
<key>CFBundleIdentifier</key><string>local.dov.warpvoice</string>
<key>CFBundleExecutable</key><string>WarpVoice</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Запись голоса для диктовки через Warp.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
echo "Built: $app"
