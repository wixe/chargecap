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
* **Bidirectional Unix Socket IPC:** Communicates over `/var/run/chargecap.sock` with kernel-level `getpeereid()` root verification for power control commands and zero network stack overhead.
* **Ultra-Lightweight:** Compiled native Swift binary is **< 300 KB** with **< 10 MB RAM** footprint, zero open TCP/UDP ports, and 0% CPU usage.

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
| **Unix Socket IPC** | ❌ None | **✅ `/var/run/chargecap.sock` (`getpeereid` secured)** |
| **Open Source** | ❌ Closed source helper binary | **✅ 100% Native Swift 6** |

---

## 🚀 Quick Start (No Compiler or Xcode Required)

### Option 1: One-Line Install
```bash
curl -fsSL https://raw.githubusercontent.com/wixe/chargecap/main/install.sh | sudo bash
```

### Option 2: Clone & Install (Uses Precompiled Universal Binary `bin/chargecap`)
```bash
git clone https://github.com/wixe/chargecap.git
cd chargecap
sudo ./install.sh
```

### Option 3: Build from Source (Optional, requires Swift)
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

# Configure micro-sailing hysteresis (requires sudo)
sudo chargecap sailing on 3

# Turn off sailing / strict cap (requires sudo)
sudo chargecap sailing off

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
  Target Limit:       50% (Micro-Sailing ±3%)
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
