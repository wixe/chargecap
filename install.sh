#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# ChargePlan Zero-Dependency Installer (Precompiled Universal Binary + Source)
# https://github.com/wixe/chargeplan
# ==============================================================================

echo "========================================================================"
echo "⚡ Installing ChargePlan — Intelligent macOS Battery Governor"
echo "========================================================================"

if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This installer must be run as root."
   echo "   Please run: sudo ./install.sh"
   exit 1
fi

INSTALL_DIR="/usr/local/bin"
mkdir -p "$INSTALL_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || pwd)"
PREBUILT_PATH="$SCRIPT_DIR/bin/chargeplan"
BIN_PATH=""

if [[ "${1:-}" == "--build" ]]; then
    echo "🔨 Compiling ChargePlan from source..."
    cd "$SCRIPT_DIR"
    swift build -c release --build-system native || swift build -c release
    if [[ -f "$SCRIPT_DIR/.build/arm64-apple-macosx/release/chargeplan" ]]; then
        BIN_PATH="$SCRIPT_DIR/.build/arm64-apple-macosx/release/chargeplan"
    else
        BIN_PATH="$SCRIPT_DIR/.build/release/chargeplan"
    fi
elif [[ -f "$PREBUILT_PATH" ]]; then
    echo "📦 Using precompiled Universal binary (bin/chargeplan)..."
    BIN_PATH="$PREBUILT_PATH"
else
    echo "⬇️  Downloading precompiled ChargePlan Universal binary from GitHub..."
    TMP_BIN="$(mktemp /tmp/chargeplan.XXXXXX)"
    curl -fsSL "https://raw.githubusercontent.com/wixe/chargeplan/main/bin/chargeplan" -o "$TMP_BIN"
    BIN_PATH="$TMP_BIN"
fi

echo "📦 Installing binary to $INSTALL_DIR/chargeplan and /Library/Application Support/ChargePlan/ChargePlanDaemon..."
mkdir -p "$INSTALL_DIR" "/Library/Application Support/ChargePlan"
rm -f "$INSTALL_DIR/chargeplan" "/Library/Application Support/ChargePlan/ChargePlanDaemon"
install -m 755 "$BIN_PATH" "$INSTALL_DIR/chargeplan"
install -m 755 "$BIN_PATH" "/Library/Application Support/ChargePlan/ChargePlanDaemon"
xattr -cr "$INSTALL_DIR/chargeplan" "/Library/Application Support/ChargePlan/ChargePlanDaemon" 2>/dev/null || true
codesign --force --sign - "$INSTALL_DIR/chargeplan" 2>/dev/null || true
codesign --force --sign - "/Library/Application Support/ChargePlan/ChargePlanDaemon" 2>/dev/null || true

if [[ "$BIN_PATH" == /tmp/chargeplan.* ]]; then
    rm -f "$BIN_PATH"
fi

echo "⚙️  Configuring LaunchDaemon..."
# Clean up legacy ChargeCap plists and running services
launchctl bootout system/com.wixe.chargecap.daemon 2>/dev/null || true
launchctl bootout system/com.wixe.chargecap 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.wixe.chargecap.plist /Library/LaunchDaemons/com.wixe.chargecap.daemon.plist 2>/dev/null || true

"$INSTALL_DIR/chargeplan" install

echo "🖥  Installing ChargePlan.app to /Applications..."
DMG_PATH="$SCRIPT_DIR/dist/ChargePlan.dmg"
TMP_DMG=""
if [[ ! -f "$DMG_PATH" ]]; then
    TMP_DMG="$(mktemp /tmp/ChargePlan.XXXXXX.dmg)"
    curl -fsSL "https://github.com/wixe/chargeplan/raw/main/dist/ChargePlan.dmg" -o "$TMP_DMG"
    DMG_PATH="$TMP_DMG"
fi

MOUNT_DIR="$(mktemp -d /tmp/chargeplan-mnt.XXXXXX)"
if hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet; then
    rm -rf "/Applications/ChargePlan.app"
    cp -R "$MOUNT_DIR/ChargePlan.app" "/Applications/ChargePlan.app"
    hdiutil detach "$MOUNT_DIR" -quiet || true
    
    CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "${SUDO_USER:-}")"
    if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" ]]; then
        chown -R "$CONSOLE_USER:admin" "/Applications/ChargePlan.app" 2>/dev/null || true
    fi
    
    xattr -cr "/Applications/ChargePlan.app" 2>/dev/null || true
    codesign --force --deep --sign - "/Applications/ChargePlan.app" 2>/dev/null || true
    
    # Remove old ChargeCap app if present
    rm -rf "/Applications/ChargeCap.app" 2>/dev/null || true
fi
rmdir "$MOUNT_DIR" 2>/dev/null || true
if [[ -n "$TMP_DMG" ]]; then
    rm -f "$TMP_DMG"
fi

echo ""
echo "✅ Installation complete! (/Applications/ChargePlan.app + Background Daemon)"
echo ""
"$INSTALL_DIR/chargeplan" status
