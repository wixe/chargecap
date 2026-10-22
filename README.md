# ChargeCap ⚡🔋

> **Intelligent, lightweight macOS battery & power governor.** Stop battery degradation, prevent silent SMC charge creep, and manage Apple Silicon & Intel batteries with closed-loop AI telemetry.

[![Build](https://github.com/wixe/chargecap/actions/workflows/build.yml/badge.svg)](https://github.com/wixe/chargecap/actions)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%20%7C%206.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Author](https://img.shields.io/badge/developer-wixe-purple.svg)](https://github.com/wixe)

---

## ⚡ What is ChargeCap?

**ChargeCap** is a native, featherweight closed-loop power governor, menu bar app, and CLI designed for Apple Silicon (M1/M2/M3/M4) and Intel MacBooks:

* **Closed-Loop SMC Verification:** Instead of writing a charge target once and hoping the hardware remembers it after sleep, lid closing, or USB-C PD negotiation, ChargeCap monitors IOKit power events continuously and re-enforces your limit in sub-second time.
* **True AC Pass-Through:** Inhibits cell charging while routing 100% of system load directly from the wall adapter (`0 mA` battery current, `0.00W` battery stress) without cutting AC input.
* **Hysteresis Deadband Control:** Prevents constant micro-trickling into lithium cells by allowing State of Charge (SoC) to float naturally within a configurable deadband window (e.g. 47%–50% for a 50% storage limit).
* **Thermal-Aware Chemistry Protection:** Automatically throttles or inhibits charging when battery or system thermal pressure rises, preventing additive thermal stress (charging heat + CPU/GPU load).
* **Menu Bar UI + Headless LaunchDaemon:** Includes a native macOS Menu Bar app (`ChargeCap.app`) with a live Settings window alongside a 24/7 root `LaunchDaemon` that operates even when no user is logged in.
* **Bidirectional Unix Socket IPC:** Communicates over `/var/run/chargecap.sock` with kernel-level `getpeereid()` root verification for power control commands and zero network stack overhead.
* **Ultra-Lightweight:** Compiled native Swift binary is **< 300 KB** with **< 10 MB RAM** footprint, zero open TCP/UDP ports, and 0% CPU usage.

---

## 📊 Architecture & Specifications

| Capability | ChargeCap Implementation |
| :--- | :--- |
| **Control Loop Architecture** | Closed-loop IOKit event observer + periodic SMC register verification |
| **Power Path Routing** | Hardware AC Pass-Through (`AppleSmartBatteryManager` / AppleSMC charge inhibit) |
| **Charge Regulation** | Configurable target setpoint (20%–100%) with **Hysteresis Deadband** (`±1%` to `±15%`) |
| **Thermal Governor** | Automatic charge inhibition under `Serious` / `Critical` IOKit thermal pressure |
| **Privilege Separation** | Read-only telemetry for standard users; kernel `getpeereid() == 0` required for writes |
| **IPC Transport** | Pure POSIX `AF_UNIX` domain socket (`/var/run/chargecap.sock`) with `500ms` timeouts |
| **Desktop & Headless Modes** | Native AppKit Menu Bar + Settings app (`ChargeCap.app`) & root `LaunchDaemon` |
| **Footprint & License** | **< 300 KB** Universal binary, **< 10 MB RAM**, **0% CPU**, **100% Open Source (MIT)** |

---

## 🚀 Quick Start (No Compiler or Terminal Required)

### Option 1: macOS Menu Bar App (`ChargeCap.dmg` — Drag & Drop)
1. Download **[`ChargeCap.dmg`](https://github.com/wixe/chargecap/raw/main/dist/ChargeCap.dmg)** and open it.
2. Drag **`ChargeCap.app`** into the **`Applications`** folder.
3. Open **`ChargeCap`** from `/Applications` — it adds the **`⚡ ChargeCap`** icon to your top-right macOS Menu Bar, opens the Settings window, and lets you install/uninstall the background governor or adjust charge limits with 1 click.

### Option 2: One-Line Terminal Install
```bash
curl -fsSL https://raw.githubusercontent.com/wixe/chargecap/main/install.sh | sudo bash
```

### Option 3: Clone & Install (Uses Precompiled Universal Binary `bin/chargecap`)
```bash
git clone https://github.com/wixe/chargecap.git
cd chargecap
sudo ./install.sh
```

### Option 4: Build from Source (Optional, requires Swift)
```bash
sudo ./install.sh --build
```

---

## 💻 CLI & Unix Socket Usage

ChargeCap includes a clean CLI and bidirectional Unix Domain Socket (`/var/run/chargecap.sock`):

```bash
# Display live battery health, voltage, wattage, and governor status (no sudo required)
chargecap status

# Output machine-readable JSON for monitoring scripts (no sudo required)
chargecap status --json

# Set target charge limit (requires sudo)
sudo chargecap set 50

# Configure hysteresis deadband (requires sudo)
sudo chargecap deadband on 3

# Turn off hysteresis deadband / strict cap (requires sudo)
sudo chargecap deadband off

# Query or control directly via Unix socket pipe
echo "STATUS" | nc -U /var/run/chargecap.sock
sudo sh -c 'echo "SET 50" | nc -U /var/run/chargecap.sock'

# Install background 24/7 LaunchDaemon
sudo chargecap install

# Uninstall LaunchDaemon
sudo chargecap uninstall
```

---

## 🖥️ Live Telemetry Output

Running `chargecap status` displays high-precision hardware diagnostics:

```text
========================================================================
⚡ CHARGECAP POWER TELEMETRY & GOVERNOR
========================================================================
  Battery Level:      55% (🔌 AC Connected (Not Charging))
  Target Limit:       50% (Hysteresis Deadband ±3%)
  Governor State:     Holding Cap at 50% (Idle AC Pass-through)
  Health Condition:   [█████████████████░░░] 86.2%
  Cycle Count:        121 cycles
  Voltage & Current:  11389 mV  •  0 mA (0.00W)
  Hardware Capacity:  3777 / 4382 mAh
  Thermal State:      Nominal
  Hardware Backend:   Direct AppleSMC Driver (AC Pass-Through)
  Serial Number:      D862125AQVYPJYRA4
========================================================================
```

---

## 🛠️ Configuration

Configuration is automatically stored at `/etc/chargecap.json` (or `~/.config/chargecap/config.json`):

```json
{
  "autoServerMode": true,
  "deadbandDelta": 3,
  "deadbandEnabled": true,
  "pollIntervalSeconds": 5.0,
  "targetLimit": 50,
  "thermalProtectionEnabled": true
}
```

---

## 📄 License

ChargeCap is open-source software licensed under the [MIT License](LICENSE).
Copyright © 2026 [Wixe](https://github.com/wixe).
