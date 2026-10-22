# ChargeCap ⚡🔋

> **Intelligent, lightweight macOS battery & power governor.** Stop battery degradation, prevent silent SMC charge creep, and manage Apple Silicon & Intel batteries with closed-loop AI telemetry.

[![Build](https://github.com/wixe/chargecap/actions/workflows/build.yml/badge.svg)](https://github.com/wixe/chargecap/actions)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%20%7C%206.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Author](https://img.shields.io/badge/developer-wixe-purple.svg)](https://github.com/wixe)

---

## ⚡ What is ChargeCap?

**ChargeCap** is a native, featherweight power management daemon and CLI designed for Apple Silicon (M1/M2/M3/M4) and Intel MacBooks. It was created to solve the fundamental reliability issues of legacy tools like AlDente:

* **Closed-Loop Verification:** Unlike AlDente—which writes a target once and fails when macOS silently resets SMC registers after sleep, lid closing, or charger negotiation—ChargeCap monitors IOKit power events continuously and re-enforces your limit in sub-second time.
* **Autonomous Micro-Sailing:** Prevents constant micro-trickling into lithium cells by letting charge gently float within an optimal hysteresis band (e.g. 47%–50% for a 50% storage limit).
* **Thermal-Aware Chemistry Protection:** Automatically throttles or inhibits charging when battery or system thermal pressure rises, preventing additive thermal stress (charging heat + CPU/GPU load).
* **Headless Fleet & Server Native:** Operates headlessly as a root `LaunchDaemon` without requiring any user to be logged into a desktop session.
* **Built-in REST API:** Serves live JSON battery metrics and control endpoints over HTTP (`:8772`) for remote fleet dashboards and home automation.
* **Ultra-Lightweight:** Compiled native Swift binary is **< 300 KB** with **< 10 MB RAM** footprint and 0% CPU usage.

---

## 📊 ChargeCap vs. AlDente

| Feature | AlDente (Free / Pro) | ChargeCap |
| :--- | :--- | :--- |
| **Price & License** | Proprietary ($14 / $30 subscription) | **100% Free & Open Source (MIT)** |
| **Binary & Memory Footprint** | ~60 MB RAM + 3% CPU background load | **< 300 KB binary, < 10 MB RAM, 0% CPU** |
| **Closed-Loop Anti-Creep** | ❌ Fails silently after sleep/wake | **✅ Sub-second verification & re-enforcement** |
| **Micro-Sailing Mode** | 🔒 Paid Pro Paywall | **✅ Built-in & configurable** |
| **Thermal Protection** | 🔒 Paid Pro Paywall | **✅ Built-in IOKit thermal governor** |
| **Headless / Server Run** | ❌ Requires logged-in GUI user session | **✅ Native 24/7 root LaunchDaemon** |
| **Remote HTTP REST API** | ❌ None | **✅ Port 8772 JSON API for fleet monitoring** |
| **Open Source** | ❌ Closed source helper binary | **✅ 100% Native Swift 6** |

---

## 🚀 Quick Start

### 1. Build & Install from Source
```bash
git clone https://github.com/wixe/chargecap.git
cd chargecap

# Build release binary and install system-wide
sudo ./install.sh
```

### 2. Manual Compilation
```bash
swift build -c release
sudo cp .build/arm64-apple-macosx/release/chargecap /usr/local/bin/
sudo chargecap install
```

---

## 💻 CLI Usage

ChargeCap includes an intuitive command-line interface:

```bash
# Display live battery health, voltage, wattage, and governor status
chargecap status

# Output machine-readable JSON for monitoring scripts
chargecap status --json

# Set target charge limit (e.g. 50% for 24/7 server, 80% for daily laptop)
chargecap set 50

# Configure micro-sailing hysteresis (e.g. sail ±3% around target)
chargecap sailing on 3

# Turn off sailing (strict hard cap)
chargecap sailing off

# Run governor daemon in foreground (for testing/debugging)
chargecap daemon

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
  Battery Level:      55% (🔌 AC Connected, Holding Cap)
  Target Limit:       50% (Micro-Sailing ±3%)
  Health Condition:   [█████████████████░░░] 85.9%
  Cycle Count:        120 cycles
  Voltage & Current:  11389 mV  •  -612 mA (6.97W)
  Hardware Capacity:  3764 / 4382 mAh
  Thermal State:      Nominal
  Hardware Backend:   Direct AppleSMC Driver
  Serial Number:      D862125AQVYPJYRA4
========================================================================
```

---

## 🌐 Remote REST API

When the daemon is active, ChargeCap exposes a lightweight HTTP server on port `8772`:

### Endpoints

| Endpoint | Method | Description |
| :--- | :--- | :--- |
| `/api/status` | `GET` | Complete JSON report (battery stats, health, governor state, thermal pressure) |
| `/api/set?limit=<20-100>` | `GET` | Dynamically change the target limit on the fly without restarting daemon |

### Example JSON Payload (`GET /api/status`)
```json
{
  "battery": {
    "amperage_ma": -612,
    "cycle_count": 120,
    "design_capacity_mah": 4382,
    "full_capacity_mah": 3764,
    "health_percent": 85.9,
    "is_ac_connected": true,
    "is_charging": false,
    "percent": 50,
    "thermal_state": "Nominal",
    "voltage_mv": 11389,
    "wattage_w": 6.97
  },
  "governor": {
    "backend": "Direct AppleSMC Driver",
    "charging_inhibited": true,
    "mode": "Holding Cap at 50% (Idle AC Pass-through)",
    "sailing_delta": 3,
    "sailing_enabled": true,
    "target_limit": 50,
    "thermal_throttled": false
  }
}
```

---

## 🛠️ Configuration

Configuration is automatically stored at `/etc/chargecap.json` (or `~/.config/chargecap/config.json`):

```json
{
  "autoServerMode": true,
  "httpEnabled": true,
  "httpPort": 8772,
  "pollIntervalSeconds": 5.0,
  "sailingDelta": 3,
  "sailingEnabled": true,
  "targetLimit": 50,
  "thermalProtectionEnabled": true
}
```

---

## 📄 License

ChargeCap is open-source software licensed under the [MIT License](LICENSE).
Copyright © 2026 [Wixe](https://github.com/wixe).
