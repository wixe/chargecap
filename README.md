# ChargePlan ⚡🔋

> **Intelligent, lightweight macOS battery & power governor.** Stop battery degradation, prevent silent SMC charge creep, and manage Apple Silicon & Intel batteries with closed-loop AI telemetry.

[![Build](https://github.com/wixe/chargeplan/actions/workflows/build.yml/badge.svg)](https://github.com/wixe/chargeplan/actions)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%20%7C%206.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Author](https://img.shields.io/badge/developer-wixe-purple.svg)](https://github.com/wixe)

---

## ⚡ What is ChargePlan?

**ChargePlan** is a native, featherweight closed-loop power governor, menu bar app, and CLI designed for Apple Silicon (M1/M2/M3/M4) and Intel MacBooks:

* **Closed-Loop SMC Verification:** Instead of writing a charge target once and hoping the hardware remembers it after sleep, lid closing, or USB-C PD negotiation, ChargePlan monitors IOKit power events continuously and re-enforces your limit in sub-second time.
* **True AC Pass-Through:** Inhibits cell charging while routing 100% of system load directly from the wall adapter (`0 mA` battery current, `0.00W` battery stress) without cutting AC input.
* **Hysteresis Deadband Control:** Prevents constant micro-trickling into lithium cells by allowing State of Charge (SoC) to float naturally within a configurable deadband window (e.g. 47%–50% for a 50% storage limit).
* **Thermal-Aware Chemistry Protection:** Automatically throttles or inhibits charging when battery or system thermal pressure rises, preventing additive thermal stress (charging heat + CPU/GPU load).
* **Menu Bar UI + Headless LaunchDaemon:** Includes a native macOS Menu Bar app (`ChargePlan.app`) with a live Settings window alongside a 24/7 root `LaunchDaemon` that operates even when no user is logged in.
* **Bidirectional Unix Socket IPC:** Communicates over `/var/run/chargeplan.sock` with kernel-level `getpeereid()` root verification for power control commands and zero network stack overhead.
* **Ultra-Lightweight:** Compiled native Swift binary is **< 300 KB** with **< 10 MB RAM** footprint, zero open TCP/UDP ports, and 0% CPU usage.

---

## 📊 Architecture & Specifications

| Capability | ChargePlan Implementation |
| :--- | :--- |
| **Control Loop Architecture** | Closed-loop IOKit event observer + periodic SMC register verification |
| **Power Path Routing** | Hardware AC Pass-Through (`AppleSmartBatteryManager` / AppleSMC charge inhibit) |
| **Charge Regulation** | Configurable target setpoint (30%–100%) with **Hysteresis Deadband** (`±1%` to `±10%`) |
| **Thermal Governor** | Automatic charge inhibition under `Serious` / `Critical` IOKit thermal pressure |
| **Privilege Separation** | Read-only telemetry for standard users; kernel `getpeereid() == 0` required for writes |
| **IPC Transport** | Pure POSIX `AF_UNIX` domain socket (`/var/run/chargeplan.sock`) with `500ms` timeouts |
| **Desktop & Headless Modes** | Native AppKit Menu Bar + Settings app (`ChargePlan.app`) & root `LaunchDaemon` |
| **Footprint & License** | **< 300 KB** Universal binary, **< 10 MB RAM**, **0% CPU**, **100% Open Source (MIT)** |

---

## 🚀 Quick Start (No Compiler or Terminal Required)

### Option 1: macOS Menu Bar App (`ChargePlan.dmg` — Drag & Drop)
1. Download **[`ChargePlan.dmg`](https://github.com/wixe/chargeplan/raw/main/dist/ChargePlan.dmg)** and open it.
2. Drag **`ChargePlan.app`** into the **`Applications`** folder.
3. Open **`ChargePlan`** from `/Applications` — it adds the **`⚡ ChargePlan`** icon to your top-right macOS Menu Bar, opens the Settings window, and lets you install/uninstall the background governor or adjust charge limits with 1 click.
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

## 💻 CLI & Unix Socket Usage

ChargePlan includes a clean CLI and bidirectional Unix Domain Socket (`/var/run/chargeplan.sock`):

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

# Query or control directly via Unix socket pipe
echo "STATUS" | nc -U /var/run/chargeplan.sock
echo "SET 50" | nc -U /var/run/chargeplan.sock

# Install background 24/7 LaunchDaemon (displays as ChargePlanDaemon in System Settings)
sudo chargeplan install

# Uninstall LaunchDaemon
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
  Hardware Backend:   Direct AppleSMC Driver (AC Pass-Through)
  Serial Number:      D862125AQVYPJYRA4
========================================================================
```

---

## 🛠️ Configuration

Configuration is automatically stored at `/etc/chargeplan.json` (or `~/.config/chargeplan/config.json`):

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

On macOS 27 (and the firmware that ships with certain 26.x / 15.x security updates), Apple gated the classic SMC charge-inhibit keys (`CHTE`, `CH0B`, `CH0C`, and the newer `bfD0`/`bfE0`/`bfF0` set) behind the private entitlement `com.apple.private.iokit.soc-limit`. Even root cannot write them.

ChargePlan automatically falls back to Apple’s own manual charge-limit mechanism inside `powerd`:

- For limits ≥ 80% it uses the public PowerUI XPC path (the same one behind System Settings → Battery → Charge Limit).
- For limits below 80% (e.g. 50%) it writes `mclLimitValue` into the `com.apple.smartcharging.topoffprotection` preference domain and posts `com.apple.smartcharging.defaultschanged`. The 80–100% range check exists only in the XPC handler; the preference-reload path forwards the value unvalidated. This engages a firmware SoC ceiling with true AC pass-through (~0 mA battery current) that holds through sleep.

Once the battery reaches the target, the Mac runs entirely from the adapter. The closed-loop governor continues to re-assert the limit after sleep, lid events, or power renegotiation. Occasional Apple calibration charges to 100% can still occur; ChargePlan will restore the limit afterward.

This path is undocumented and may change in a future macOS update. The hardware backend reported by `chargeplan status` will show **macOS Native PowerUI (AC Pass-Through)** when this mode is active.

---

## 📄 License

ChargePlan is open-source software licensed under the [MIT License](LICENSE).
Copyright © 2026 [Wixe](https://github.com/wixe).
