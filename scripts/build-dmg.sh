#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

BUILD_SCRATCH="/tmp/chargecap-dmg-build"
DIST_DIR="$SCRIPT_DIR/dist"
STAGING_DIR="/tmp/chargecap-dmg-staging"
APP_BUNDLE="$STAGING_DIR/ChargeCap.app"
DMG_PATH="$DIST_DIR/ChargeCap.dmg"

echo "🔨 Building Universal CLI & Menu Bar App (arm64 + x86_64)..."
swift build -c release --build-system native --scratch-path "$BUILD_SCRATCH" --arch arm64
swift build -c release --build-system native --scratch-path "$BUILD_SCRATCH" --arch x86_64

mkdir -p "$SCRIPT_DIR/bin" "$DIST_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

echo "🧬 Creating Universal binaries with lipo..."
lipo -create \
    "$BUILD_SCRATCH/arm64-apple-macosx/release/chargecap" \
    "$BUILD_SCRATCH/x86_64-apple-macosx/release/chargecap" \
    -output "$SCRIPT_DIR/bin/chargecap"
strip -x "$SCRIPT_DIR/bin/chargecap"
codesign --force --sign - "$SCRIPT_DIR/bin/chargecap"

lipo -create \
    "$BUILD_SCRATCH/arm64-apple-macosx/release/ChargeCapApp" \
    "$BUILD_SCRATCH/x86_64-apple-macosx/release/ChargeCapApp" \
    -output "$APP_BUNDLE/Contents/MacOS/ChargeCapApp"
strip -x "$APP_BUNDLE/Contents/MacOS/ChargeCapApp"

cp "$SCRIPT_DIR/bin/chargecap" "$APP_BUNDLE/Contents/Resources/chargecap"
chmod 755 "$APP_BUNDLE/Contents/MacOS/ChargeCapApp" "$APP_BUNDLE/Contents/Resources/chargecap"

VERSION="$(grep 'public let ChargeCapVersion =' Sources/ChargeCapCore/UpdateChecker.swift | cut -d '"' -f2)"

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ChargeCapApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.wixe.chargecap.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ChargeCap</string>
    <key>CFBundleDisplayName</key>
    <string>ChargeCap</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

codesign --force --deep --sign - "$APP_BUNDLE"

# Create /Applications symlink for Drag-and-Drop DMG
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 Packaging Drag-and-Drop DMG ($DMG_PATH)..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "ChargeCap" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Copy ChargeCap.app into /Applications on this Mac as well
rm -rf /Applications/ChargeCap.app
cp -R "$APP_BUNDLE" /Applications/ChargeCap.app

rm -rf "$BUILD_SCRATCH" "$STAGING_DIR"

echo "✅ Built $DMG_PATH and installed /Applications/ChargeCap.app"
ls -lh "$DMG_PATH"
