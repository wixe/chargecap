#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# ChargeCap Zero-Dependency Installer (Precompiled Universal Binary + Source)
# https://github.com/wixe/chargecap
# ==============================================================================

echo "========================================================================"
echo "⚡ Installing ChargeCap — Intelligent macOS Battery Governor"
echo "========================================================================"

if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This installer must be run as root."
   echo "   Please run: sudo ./install.sh"
   exit 1
fi

INSTALL_DIR="/usr/local/bin"
mkdir -p "$INSTALL_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || pwd)"
PREBUILT_PATH="$SCRIPT_DIR/bin/chargecap"
BIN_PATH=""

if [[ "${1:-}" == "--build" ]]; then
    echo "🔨 Compiling ChargeCap from source..."
    cd "$SCRIPT_DIR"
    swift build -c release --build-system native || swift build -c release
    if [[ -f "$SCRIPT_DIR/.build/arm64-apple-macosx/release/chargecap" ]]; then
        BIN_PATH="$SCRIPT_DIR/.build/arm64-apple-macosx/release/chargecap"
    else
        BIN_PATH="$SCRIPT_DIR/.build/release/chargecap"
    fi
elif [[ -f "$PREBUILT_PATH" ]]; then
    echo "📦 Using precompiled Universal binary (bin/chargecap)..."
    BIN_PATH="$PREBUILT_PATH"
else
    echo "⬇️  Downloading precompiled ChargeCap Universal binary from GitHub..."
    TMP_BIN="$(mktemp /tmp/chargecap.XXXXXX)"
    curl -fsSL "https://raw.githubusercontent.com/wixe/chargecap/main/bin/chargecap" -o "$TMP_BIN"
    BIN_PATH="$TMP_BIN"
fi

echo "📦 Installing binary to $INSTALL_DIR/chargecap..."
rm -f "$INSTALL_DIR/chargecap"
install -m 755 "$BIN_PATH" "$INSTALL_DIR/chargecap"
xattr -cr "$INSTALL_DIR/chargecap" 2>/dev/null || true
codesign --force --sign - "$INSTALL_DIR/chargecap" 2>/dev/null || true

if [[ "$BIN_PATH" == /tmp/chargecap.* ]]; then
    rm -f "$BIN_PATH"
fi

echo "⚙️  Configuring LaunchDaemon..."
"$INSTALL_DIR/chargecap" install

echo "🖥  Installing ChargeCap.app to /Applications..."
DMG_PATH="$SCRIPT_DIR/dist/ChargeCap.dmg"
TMP_DMG=""
if [[ ! -f "$DMG_PATH" ]]; then
    TMP_DMG="$(mktemp /tmp/ChargeCap.XXXXXX.dmg)"
    curl -fsSL "https://github.com/wixe/chargecap/raw/main/dist/ChargeCap.dmg" -o "$TMP_DMG"
    DMG_PATH="$TMP_DMG"
fi

MOUNT_DIR="$(mktemp -d /tmp/chargecap-mnt.XXXXXX)"
if hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet; then
    rm -rf "/Applications/ChargeCap.app"
    cp -R "$MOUNT_DIR/ChargeCap.app" "/Applications/ChargeCap.app"
    hdiutil detach "$MOUNT_DIR" -quiet || true
    xattr -cr "/Applications/ChargeCap.app" 2>/dev/null || true
    codesign --force --deep --sign - "/Applications/ChargeCap.app" 2>/dev/null || true
fi
rmdir "$MOUNT_DIR" 2>/dev/null || true
if [[ -n "$TMP_DMG" ]]; then
    rm -f "$TMP_DMG"
fi

echo ""
echo "✅ Installation complete! (/Applications/ChargeCap.app + Background Daemon)"
echo ""
"$INSTALL_DIR/chargecap" status
