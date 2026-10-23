# ChargePlan ⚡🔋

> **Native, lightweight macOS battery & power governor.** Stop battery degradation, prevent hardware charge creep, and maintain custom charge ceilings with closed-loop telemetry.

[![Build](https://github.com/wixe/chargeplan/actions/workflows/build.yml/badge.svg)](https://github.com/wixe/chargeplan/actions)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%20%7C%206.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Author](https://img.shields.io/badge/developer-wixe-purple.svg)](https://github.com/wixe)

---

## ⚡ What is ChargePlan?

**ChargePlan** is a native, featherweight power governor, menu bar app, and CLI utility designed for Apple Silicon (M1/M2/M3/M4) and Intel MacBooks:

* **Closed-Loop Hardware Verification:** Instead of writing a charge target once and hoping the hardware remembers it after sleep, lid closing, or USB-C PD negotiation, ChargePlan monitors system power events and continuously re-asserts your configured limit.
* **True AC Pass-Through:** Inhibits cell charging while powering system load directly from the wall adapter (`0 mA` battery current, `0.00W` battery stress) without cutting AC input.
* **Hysteresis Deadband Control:** Prevents constant micro-trickling into lithium cells by allowing State of Charge (SoC) to float naturally within a configurable window (e.g. 47%–50% for a 50% storage limit).
* **Thermal-Aware Chemistry Protection:** Automatically throttles or pauses charging when system or battery thermal pressure rises, reducing additive heat stress.
* **Menu Bar App & Background Service:** Includes a native macOS Menu Bar app (`ChargePlan.app`) with a live Settings dashboard alongside a standard macOS system service so limits remain enforced even when logged out or sleeping.
* **Local IPC Control:** Communicates locally via `/var/run/chargeplan.sock` with standard POSIX peer credential validation, keeping controls secure without opening any network ports.
* **Ultra-Lightweight:** Compiled native Swift binary is **< 300 KB** with **< 10 MB RAM** footprint, zero open TCP/UDP ports, and 0% CPU usage.

---

## 📊 Architecture & Specifications

| Capability | ChargePlan Implementation |
| :--- | :--- |
| **Control Loop Architecture** | Closed-loop power event observer + periodic hardware register verification |
| **Power Path Routing** | Hardware AC Pass-Through (`AppleSmartBatteryManager` / system power management) |
| **Charge Regulation** | Configurable target setpoint (30%–100%) with **Hysteresis Deadband** (`±1%` to `±10%`) |
| **Thermal Protection** | Automatic charge inhibition under elevated IOKit thermal pressure |
| **Security & Access** | Non-privileged read telemetry; administrative group or console ownership for setting limits |
| **IPC Transport** | Local POSIX domain socket (`/var/run/chargeplan.sock`) with standard timeouts |
| **Operating Modes** | Native AppKit Menu Bar app (`ChargePlan.app`) and background system service |
| **Footprint & License** | **< 300 KB** Universal binary, **< 10 MB RAM**, **0% CPU**, **100% Open Source (MIT)** |

---

## 🚀 Quick Start (No Compiler or Terminal Required)

### Option 1: macOS Menu Bar App (`ChargePlan.dmg` — Drag & Drop)
1. Download **[`ChargePlan.dmg`](https://github.com/wixe/chargeplan/releases/latest/download/ChargePlan.dmg)** and open it.
2. Drag **`ChargePlan.app`** into the **`Applications`** folder.
3. Open **`ChargePlan`** from `/Applications` — it adds the **`⚡ ChargePlan`** icon to your top-right macOS Menu Bar, opens the Settings window, and lets you manage background services or adjust charge limits with 1 click.
   > **Note on macOS Gatekeeper:** Because ChargePlan is free, open-source software signed ad-hoc (`codesign --sign -`), macOS may show an *"unverified developer"* prompt the first time you open a browser-downloaded `.dmg`. Either click **Open Anyway** in **System Settings → Privacy & Security**, or run `xattr -cr /Applications/ChargePlan.app` once in Terminal (or use Option 2 below, which bypasses browser quarantine automatically).

### Option 2: One-Line Terminal Install
```bash
curl -fsSL https://raw.githubusercontent.com/wixe/chargeplan/main/install.sh | sudo bash
```

### Option 3: Clone & Install (Uses Precompiled Universal Binary `bin/chargeplan`)
```bash
git clone https://github.com/wixe/chargeplan.git
cd chargeplan
sudo ./install.sh
```

### Option 4: Build from Source (Optional, requires Swift)
```bash
sudo ./install.sh --build
```

---

## 💻 CLI & Local Socket Usage

ChargePlan includes a clean CLI and local Unix Domain Socket (`/var/run/chargeplan.sock`):

```bash
# Display live battery health, voltage, wattage, and governor status (no sudo required)
chargeplan status

# Output machine-readable JSON for monitoring scripts (no sudo required)
chargeplan status --json

# Set target charge limit (requires sudo or running daemon)
chargeplan set 50

# Configure hysteresis deadband (requires sudo or running daemon)
chargeplan deadband on 3

# Turn off hysteresis deadband / strict cap (requires sudo or running daemon)
chargeplan deadband off

# Query or control directly via local socket
echo "STATUS" | nc -U /var/run/chargeplan.sock
echo "SET 50" | nc -U /var/run/chargeplan.sock

# Install background service (keeps limits enforced when sleeping or logged out)
sudo chargeplan install

# Uninstall background service
sudo chargeplan uninstall

# Check for updates or upgrade CLI & Menu Bar App from GitHub
chargeplan update --check
sudo chargeplan update
```

---

## 🖥️ Live Telemetry Output

Running `chargeplan status` displays high-precision hardware diagnostics:

```text
========================================================================
⚡ CHARGEPLAN POWER TELEMETRY & GOVERNOR
========================================================================
  Battery Level:      55% (🔌 AC Connected (Not Charging))
  Target Limit:       50% (Deadband -3%)
  Governor State:     Holding Cap at 50% (Idle AC Pass-through)
  Health Condition:   [██████████████████░░] 86.2%
  Cycle Count:        121 cycles
  Voltage & Current:  11389 mV  •  0 mA (0.00W)
  Hardware Capacity:  3777 / 4382 mAh
  Thermal State:      Nominal
  Hardware Backend:   macOS Native PowerUI (AC Pass-Through)
  Serial Number:      D862125AQVYPJYRA4
========================================================================
```

---

## 🛠️ Configuration

Configuration is stored at `/etc/chargeplan.json` (or `~/.config/chargeplan/config.json`):

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

## macOS 27 (Golden Gate) Notes

On macOS 27 (and firmware shipping with recent security updates), Apple gated legacy SMC charge-inhibit keys behind private entitlements. 

ChargePlan automatically uses Apple’s native manual charge-limit mechanism inside `powerd`:

- For limits ≥ 80% it uses the public PowerUI XPC path (the same backend used by System Settings → Battery → Charge Limit).
- For limits below 80% (e.g. 50%) it writes to `com.apple.smartcharging.topoffprotection` and notifies `powerd`. The 80–100% boundary check exists only in Apple's front-end UI; the system preference forwards the value to hardware directly. This engages a firmware SoC ceiling with true AC pass-through (~0 mA battery current) that holds through sleep.

Once the battery reaches the target, the Mac runs entirely from the adapter. The governor continues to re-assert the limit after sleep, lid events, or power renegotiation.

The hardware backend reported by `chargeplan status` displays **macOS Native PowerUI (AC Pass-Through)** when this mode is active.

---

## ⚠️ Disclaimer

> [!CAUTION]
> **Use at your own risk.** ChargePlan interfaces directly with low-level macOS power management and battery charging subsystems. While designed with safety boundaries and thermal fail-safes, **the developer is not responsible for any hardware damage, battery degradation, data loss, voided warranties, or system issues** resulting from the use of this software. This software is provided "as is", without warranty of any kind.

---

## 📄 License

ChargePlan is open-source software licensed under the [MIT License](LICENSE).
Copyright © 2026 [Wixe](https://github.com/wixe).
