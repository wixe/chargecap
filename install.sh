#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# ChargeCap Installation Script
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔨 Compiling ChargeCap release binary..."
cd "$SCRIPT_DIR"
swift build -c release --build-system native || swift build -c release

BIN_PATH="$SCRIPT_DIR/.build/arm64-apple-macosx/release/chargecap"
if [[ ! -f "$BIN_PATH" ]]; then
    BIN_PATH="$SCRIPT_DIR/.build/release/chargecap"
fi

echo "📦 Installing binary to $INSTALL_DIR/chargecap..."
rm -f "$INSTALL_DIR/chargecap"
install -m 755 "$BIN_PATH" "$INSTALL_DIR/chargecap"
codesign --force --sign - "$INSTALL_DIR/chargecap" 2>/dev/null || true

echo "⚙️  Configuring LaunchDaemon..."
"$INSTALL_DIR/chargecap" install

echo ""
echo "✅ Installation complete!"
echo ""
"$INSTALL_DIR/chargecap" status
