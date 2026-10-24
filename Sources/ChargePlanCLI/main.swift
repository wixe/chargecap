import Foundation
import ChargePlanCore

let VERSION = ChargePlanVersion

func printHelp() {
    print("""
    ⚡ ChargePlan — Intelligent, Lightweight Battery & Power Management for macOS
    Version \(VERSION) (Apple Silicon M-Series)
    Website: https://github.com/wixe/chargeplan
    
    USAGE:
      chargeplan <command> [options]
    
    COMMANDS:
      status [--json]           Display battery health, power telemetry, and governor status
      set <limit>               Set target charge limit (e.g. 50, 80)
      drift <on|off> [margin]   Configure drift margin (e.g. drift on 3)
      daemon                    Run the power governor in the foreground
      install                   Install background system service (keeps limit active when sleeping or logged out)
      uninstall                 Remove background system service
      update [--check|--force]  Check GitHub and automatically upgrade binary and .app
      version                   Print version information
    
    EXAMPLES:
      chargeplan status
      sudo chargeplan set 50
      sudo chargeplan drift on 3
      sudo chargeplan install
      sudo chargeplan update
    """)
}

var ipcServer: UnixSocketServer? = nil

func handleStatus(jsonOutput: Bool) {
    if jsonOutput {
        if let liveJson = UnixSocketClient.send("STATUS") {
            print(liveJson.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        let cfg = ConfigManager.shared.load()
        let governor = AIGovernor(config: cfg)
        let report = governor.getCombinedReport()
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        return
    }
    
    let monitor = BatteryMonitor()
    let status = monitor.getCurrentStatus()
    let cfg = ConfigManager.shared.load()
    let hw = HardwareBackend()
    
    var governorMode = "Offline (Run 'sudo chargeplan install')"
    var ceilingLine = ""
    if let liveJson = UnixSocketClient.send("STATUS"),
       let data = liveJson.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let gov = obj["governor"] as? [String: Any] {
        if let mode = gov["mode"] as? String {
            governorMode = mode
        }
        if let soc = gov["enforced_soc"] as? Int, soc > 0 {
            ceilingLine = "\n  powerd Ceiling:     \(soc)%"
        }
    }
    
    let isAC = status.isACConnected
    let chargingStr = status.isCharging ? "⚡ Charging" : (isAC ? "🔌 AC Connected (Not Charging)" : "🔋 Discharging")
    let wattageStr = String(format: "%.2fW", abs(status.wattageW))
    let healthBarLength = 20
    let filledHealth = Int((status.healthPercent / 100.0) * Double(healthBarLength))
    let bar = String(repeating: "█", count: max(0, min(healthBarLength, filledHealth))) +
              String(repeating: "░", count: max(0, healthBarLength - filledHealth))
    
    var cellDetails = ""
    if !status.cellVoltagesMV.isEmpty {
        let cellsFormatted = status.cellVoltagesMV.enumerated().map { "Cell \($0.offset + 1): \($0.element) mV" }.joined(separator: "  •  ")
        let delta = status.cellImbalanceMV != nil ? " (Δ \(status.cellImbalanceMV!) mV)" : ""
        cellDetails = "\n  Cell Voltages:      \(cellsFormatted)\(delta)"
    }
    var tempDetails = ""
    if let t = status.temperatureC {
        let fahrenheit = t * 9.0 / 5.0 + 32.0
        tempDetails = String(format: "\n  Battery Temp:       %.1f°C (%.1f°F)", t, fahrenheit)
    }
    
    print("""
    ========================================================================
    ⚡ CHARGEPLAN POWER TELEMETRY & CONTROLLER
    ========================================================================
      Battery Level:      \(String(format: "%.2f%%", status.exactPercent)) (\(chargingStr))
      Target Limit:       \(cfg.targetLimit)% \(cfg.driftEnabled ? "(Drift -\(cfg.driftMargin)%)" : "(Strict)")
      Control Mode:       \(governorMode)\(ceilingLine)
      Health Condition:   [\(bar)] \(status.healthPercent)%
      Cycle Count:        \(status.cycleCount) cycles
      Voltage & Current:  \(status.voltageMV) mV  •  \(status.amperageMA) mA (\(wattageStr))
      Hardware Capacity:  \(status.remainingCapacityMAh > 0 ? "\(status.remainingCapacityMAh) / " : "")\(status.fullChargeCapacityMAh) / \(status.designCapacityMAh) mAh\(cellDetails)\(tempDetails)
      Thermal State:      \(status.thermalState)
      Hardware Backend:   \(hw.modeName)
      Serial Number:      \(status.serialNumber)
      Icon Legend:        ⚡ Charging  •  🔌 AC Pass-Through (Hold)  •  🔋 On Battery
    ========================================================================
    """)
    
    if let cachedData = UserDefaults.standard.data(forKey: "io.github.wixe.chargeplan.cachedReleaseInfo") ?? UserDefaults.standard.data(forKey: "com.wixe.chargeplan.cachedReleaseInfo"),
       let cached = try? JSONDecoder().decode(ReleaseInfo.self, from: cachedData),
       UpdateChecker.isVersion(cached.version, newerThan: ChargePlanVersion) {
        print("💡 Update available: \(cached.tagName) — Run 'sudo chargeplan update' to upgrade.\n")
    }
}

func handleSet(args: [String]) {
    guard let first = args.first, let val = Int(first), (30...100).contains(val) else {
        print("❌ Error: Please specify a valid limit between 30 and 100 (e.g. 'chargeplan set 50')")
        exit(1)
    }
    
    // 1. If background daemon is running, send command via socket (zero-sudo for console user / root)
    if let resp = UnixSocketClient.send("SET \(val)") {
        if resp.contains("\"success\":true") {
            print("✅ ChargePlan daemon updated via socket: target limit is now \(val)%.")
            return
        } else if resp.contains("Permission denied") {
            print("❌ Permission denied by daemon. Please run with sudo: sudo chargeplan set \(val)")
            exit(1)
        }
    }
    
    // 2. Direct modification requires root if daemon is not running
    guard getuid() == 0 else {
        print("❌ Power control requires root privileges (or start background daemon with 'sudo chargeplan install'):\n   sudo chargeplan set \(val)")
        exit(1)
    }
    
    var cfg = ConfigManager.shared.load()
    cfg.targetLimit = val
    if ConfigManager.shared.save(cfg) {
        let hw = HardwareBackend()
        _ = hw.setChargeLimitPercentage(val, delta: cfg.driftEnabled ? cfg.driftMargin : 1)
        print("✅ Saved target charge limit: \(val)%")
    } else {
        print("⚠️ Warning: Could not write configuration. Try running with 'sudo'.")
    }
}

func handleDrift(args: [String]) {
    guard let first = args.first?.lowercased() else {
        print("❌ Usage: chargeplan drift <on|off> [margin_percent]")
        exit(1)
    }
    
    let enabled = (first == "on" || first == "true" || first == "1")
    var margin = 3
    if args.count > 1, let m = Int(args[1]), (1...10).contains(m) {
        margin = m
    }
    
    // 1. If background daemon is running, send command via socket (zero-sudo for console user / root)
    if let resp = UnixSocketClient.send("DRIFT \(enabled ? "on" : "off") \(margin)") {
        if resp.contains("\"success\":true") {
            print("✅ Drift margin updated via socket: \(enabled ? "ENABLED (-\(margin)%)" : "DISABLED")")
            return
        } else if resp.contains("Permission denied") {
            print("❌ Permission denied by daemon. Please run with sudo: sudo chargeplan drift \(args.joined(separator: " "))")
            exit(1)
        }
    }
    
    // 2. Direct modification requires root if daemon is not running
    guard getuid() == 0 else {
        print("❌ Power control requires root privileges (or start background daemon with 'sudo chargeplan install'):\n   sudo chargeplan drift \(args.joined(separator: " "))")
        exit(1)
    }
    
    var cfg = ConfigManager.shared.load()
    cfg.driftEnabled = enabled
    cfg.driftMargin = margin
    if ConfigManager.shared.save(cfg) {
        let hw = HardwareBackend()
        _ = hw.setChargeLimitPercentage(cfg.targetLimit, delta: enabled ? margin : 1)
        print("✅ Drift margin updated: \(enabled ? "ENABLED (-\(margin)%)" : "DISABLED")")
    } else {
        print("⚠️ Warning: Could not write configuration. Try running with 'sudo'.")
    }
}

func handleDaemon() {
    print("🚀 Starting ChargePlan Controller Daemon...")
    
    // Auto-migrate legacy LaunchDaemon plist if running as root
    if getuid() == 0 && FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.wixe.chargeplan.daemon.plist") {
        let legacyPlist = "/Library/LaunchDaemons/com.wixe.chargeplan.daemon.plist"
        let newPlist = "/Library/LaunchDaemons/io.github.wixe.chargeplan.daemon.plist"
        if !FileManager.default.fileExists(atPath: newPlist) {
            if let content = try? String(contentsOfFile: legacyPlist, encoding: .utf8) {
                let updated = content.replacingOccurrences(of: "com.wixe.chargeplan.daemon", with: "io.github.wixe.chargeplan.daemon")
                try? updated.write(toFile: newPlist, atomically: true, encoding: .utf8)
                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["644", newPlist]
                try? chmod.run()
                chmod.waitUntilExit()
            }
        }
        try? FileManager.default.removeItem(atPath: legacyPlist)
    }
    
    let cfg = ConfigManager.shared.load()
    let governor = AIGovernor(config: cfg)
    governor.start()
    
    let server = UnixSocketServer(governor: governor)
    server.start()
    ipcServer = server
    print("🔌 ChargePlan Unix Socket listening at \(UnixSocketServer.defaultSocketPath)")
    
    // Register signal handler for clean shutdown
    signal(SIGINT) { _ in
        print("\n🛑 ChargePlan daemon terminating...")
        ipcServer?.stop()
        exit(0)
    }
    signal(SIGTERM) { _ in
        print("\n🛑 ChargePlan daemon terminating...")
        ipcServer?.stop()
        exit(0)
    }
    
    RunLoop.main.run()
}

func handleInstall() {
    guard getuid() == 0 else {
        print("❌ Installation requires root privileges. Please run:\n   sudo chargeplan install")
        exit(1)
    }
    
    let selfPath = CommandLine.arguments[0]
    let binSource: String
    if FileManager.default.isExecutableFile(atPath: selfPath) && !selfPath.contains("ChargePlanDaemon") {
        binSource = selfPath
    } else if FileManager.default.fileExists(atPath: "/usr/local/bin/chargeplan") {
        binSource = "/usr/local/bin/chargeplan"
    } else {
        binSource = selfPath
    }
    
    let daemonDir = "/Library/Application Support/ChargePlan"
    let daemonBin = "\(daemonDir)/ChargePlanDaemon"
    try? FileManager.default.createDirectory(atPath: daemonDir, withIntermediateDirectories: true)
    
    // Copy binary as ChargePlanDaemon so macOS System Settings displays "ChargePlanDaemon"
    let cpDaemon = Process()
    cpDaemon.executableURL = URL(fileURLWithPath: "/bin/cp")
    cpDaemon.arguments = ["-f", binSource, daemonBin]
    try? cpDaemon.run()
    cpDaemon.waitUntilExit()
    
    let chmodDaemon = Process()
    chmodDaemon.executableURL = URL(fileURLWithPath: "/bin/chmod")
    chmodDaemon.arguments = ["755", daemonBin]
    try? chmodDaemon.run()
    chmodDaemon.waitUntilExit()
    
    let xattrDaemon = Process()
    xattrDaemon.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
    xattrDaemon.arguments = ["-cr", daemonBin]
    try? xattrDaemon.run()
    xattrDaemon.waitUntilExit()
    
    let codesignDaemon = Process()
    codesignDaemon.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    codesignDaemon.arguments = ["--force", "--sign", "-", daemonBin]
    try? codesignDaemon.run()
    codesignDaemon.waitUntilExit()
    
    // Ensure /usr/local/bin/chargeplan exists for terminal usage
    if !FileManager.default.fileExists(atPath: "/usr/local/bin/chargeplan") {
        try? FileManager.default.createDirectory(atPath: "/usr/local/bin", withIntermediateDirectories: true)
        let cpCli = Process()
        cpCli.executableURL = URL(fileURLWithPath: "/bin/cp")
        cpCli.arguments = ["-f", daemonBin, "/usr/local/bin/chargeplan"]
        try? cpCli.run()
        cpCli.waitUntilExit()
        
        let chmodCli = Process()
        chmodCli.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodCli.arguments = ["755", "/usr/local/bin/chargeplan"]
        try? chmodCli.run()
        chmodCli.waitUntilExit()
        
        let codesignCli = Process()
        codesignCli.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesignCli.arguments = ["--force", "--sign", "-", "/usr/local/bin/chargeplan"]
        try? codesignCli.run()
        codesignCli.waitUntilExit()
    }
    
    let plistContent = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>io.github.wixe.chargeplan.daemon</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(daemonBin)</string>
            <string>daemon</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>/var/log/chargeplan.log</string>
        <key>StandardErrorPath</key>
        <string>/var/log/chargeplan.error.log</string>
    </dict>
    </plist>
    """
    
    let plistPath = "/Library/LaunchDaemons/io.github.wixe.chargeplan.daemon.plist"
    
    // Bootout existing legacy or current label
    for label in ["io.github.wixe.chargeplan.daemon", "com.wixe.chargeplan.daemon", "com.wixe.chargecap.daemon", "com.wixe.chargecap"] {
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "system/\(label)"]
        try? bootout.run()
        bootout.waitUntilExit()
    }
    
    // Remove legacy plists so macOS BTM cleans up old entries
    try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.wixe.chargeplan.daemon.plist")
    try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.wixe.chargecap.plist")
    try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.wixe.chargecap.daemon.plist")
    
    do {
        try plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["644", plistPath]
        try? chmod.run()
        chmod.waitUntilExit()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Bootstrap new
        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", "system", plistPath]
        try? bootstrap.run()
        bootstrap.waitUntilExit()
        
        // Ensure running daemon is restarted
        let kickstart = Process()
        kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        kickstart.arguments = ["kickstart", "-k", "system/io.github.wixe.chargeplan.daemon"]
        try? kickstart.run()
        kickstart.waitUntilExit()
        
        print("✅ ChargePlan LaunchDaemon installed and bootstrapped successfully!")
        print("   Daemon name: ChargePlanDaemon (\(daemonBin))")
        print("   CLI command: chargeplan (/usr/local/bin/chargeplan)")
        print("   Plist: \(plistPath)")
        print("   Logs:  /var/log/chargeplan.log")
    } catch {
        print("❌ Failed to install LaunchDaemon: \(error.localizedDescription)")
        exit(1)
    }
}

func handleUninstall() {
    guard getuid() == 0 else {
        print("❌ Uninstallation requires root privileges. Please run:\n   sudo chargeplan uninstall")
        exit(1)
    }
    
    // Restore normal charging before removing daemon
    let hw = HardwareBackend()
    _ = hw.setChargingInhibited(false)
    _ = hw.setChargeLimitPercentage(100)
    
    for label in ["io.github.wixe.chargeplan.daemon", "com.wixe.chargeplan.daemon", "com.wixe.chargecap.daemon", "com.wixe.chargecap"] {
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "system/\(label)"]
        try? bootout.run()
        bootout.waitUntilExit()
    }
    
    try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/io.github.wixe.chargeplan.daemon.plist")
    try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.wixe.chargeplan.daemon.plist")
    try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.wixe.chargecap.daemon.plist")
    try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.wixe.chargecap.plist")
    try? FileManager.default.removeItem(atPath: "/Library/Application Support/ChargePlan")
    try? FileManager.default.removeItem(atPath: "/Library/Application Support/ChargeCap")
    try? FileManager.default.removeItem(atPath: "/var/run/chargeplan.sock")
    try? FileManager.default.removeItem(atPath: "/var/run/chargecap.sock")
    print("✅ ChargePlan LaunchDaemon uninstalled successfully.")
}

func handleUpdate(args: [String]) {
    let checkOnly = args.contains("--check")
    let force = args.contains("--force")
    
    print("🔍 Checking GitHub for updates (current version: v\(VERSION))...")
    
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        defer { semaphore.signal() }
        guard let info = await UpdateChecker.checkForUpdate(currentVersion: VERSION, force: true) else {
            print("⚠️ Could not fetch update information from GitHub (offline or rate-limited).")
            return
        }
        
        if !info.isNewer && !force {
            print("✅ ChargePlan is already up to date! (v\(VERSION))")
            return
        }
        
        print("""
        ========================================================================
        ⬆️  New version available: \(info.tagName) (Current: v\(VERSION))
        ========================================================================
        \(info.releaseNotes.isEmpty ? "No release notes provided." : info.releaseNotes)
        ========================================================================
        """)
        
        if checkOnly {
            print("Run 'sudo chargeplan update' to install.")
            return
        }
        
        if getuid() != 0 {
            // Check if user has write access to /Applications/ChargePlan.app and daemon socket is active
            let appPath = "/Applications/ChargePlan.app"
            let appWritable = FileManager.default.isWritableFile(atPath: appPath) || FileManager.default.isWritableFile(atPath: "/Applications")
            let socketActive = FileManager.default.fileExists(atPath: "/var/run/chargeplan.sock")
            if appWritable && socketActive && !info.dmgUrl.isEmpty {
                print("⚡ Updating ChargePlan.app and background daemon via root IPC (no sudo required)…")
                do {
                    guard let dmgUrl = URL(string: info.dmgUrl) else {
                        print("❌ Invalid DMG URL: \(info.dmgUrl)")
                        exit(1)
                    }
                    try await UpdateChecker.installAppUpdate(dmgUrl: dmgUrl, relaunch: false) { step in
                        print("   → \(step)")
                    }
                    print("✅ ChargePlan successfully updated to \(info.tagName)!")
                    return
                } catch {
                    print("⚠️ Non-root update could not complete (\(error.localizedDescription)). Retrying with sudo requirement.")
                }
            }
            
            print("❌ Root privileges required to install update. Please run:\n   sudo chargeplan update")
            exit(1)
        }
        
        do {
            guard let binUrl = URL(string: info.binaryUrl) else {
                print("❌ Invalid binary download URL: \(info.binaryUrl)")
                exit(1)
            }
            try await UpdateChecker.installCLIUpdate(binaryUrl: binUrl) { step in
                print("   → \(step)")
            }
            
            // If /Applications/ChargePlan.app exists, update it too
            if FileManager.default.fileExists(atPath: "/Applications/ChargePlan.app"),
               let dmgUrl = URL(string: info.dmgUrl) {
                print("🖥  Updating /Applications/ChargePlan.app...")
                try await UpdateChecker.installAppUpdate(dmgUrl: dmgUrl, relaunch: false) { step in
                    print("   → \(step)")
                }
            }
            
            print("✅ ChargePlan successfully updated to \(info.tagName)!")
        } catch {
            print("❌ Update failed: \(error.localizedDescription)")
            exit(1)
        }
    }
    semaphore.wait()
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first?.lowercased() else {
    handleStatus(jsonOutput: false)
    exit(0)
}

switch command {
case "status":
    let isJson = args.contains("--json")
    handleStatus(jsonOutput: isJson)
case "set":
    handleSet(args: Array(args.dropFirst()))
case "drift", "deadband":
    handleDrift(args: Array(args.dropFirst()))
case "daemon":
    handleDaemon()
case "install":
    handleInstall()
case "uninstall":
    handleUninstall()
case "update":
    handleUpdate(args: Array(args.dropFirst()))
case "version", "--version", "-v":
    print("ChargePlan version \(VERSION)")
case "help", "--help", "-h":
    printHelp()
default:
    print("Unknown command: '\(command)'")
    printHelp()
    exit(1)
}
