#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building VK01Programmer and vk01-cli..."
swift build -c release

APP_DIR="VK01Programmer.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/VK01Programmer" "$APP_DIR/Contents/MacOS/VK01Programmer"
cp ".build/release/vk01-cli" "$APP_DIR/Contents/MacOS/vk01-cli"

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VK01Programmer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.anticater.vk01programmer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>VK-01 Programmer</string>
    <key>CFBundleDisplayName</key>
    <string>VK-01 Programmer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>VK-01 Programmer uses Bluetooth Low Energy to read and program your Anticater VK-01 dial.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>VK-01 Programmer uses Bluetooth Low Energy to read and program your Anticater VK-01 dial.</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "Created macOS application bundle at: $(pwd)/$APP_DIR"
