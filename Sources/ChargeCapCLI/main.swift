import Foundation
import ChargeCapCore

let VERSION = ChargeCapVersion

func printHelp() {
    print("""
    ⚡ ChargeCap — Intelligent, Lightweight Battery & Power Management for macOS
    Version \(VERSION) (Apple Silicon & Intel)
    Website: https://github.com/wixe/chargecap
    
    USAGE:
      chargecap <command> [options]
    
    COMMANDS:
      status [--json]           Display battery health, power telemetry, and governor status
      set <limit>               Set target charge limit (e.g. 50, 80)
      deadband <on|off> [delta] Configure hysteresis deadband (e.g. deadband on 3)
      daemon                    Run the AI power management governor in the foreground
      install                   Install and bootstrap background LaunchDaemon (runs 24/7 as root)
      uninstall                 Remove and unload background LaunchDaemon
      update [--check|--force]  Check GitHub and automatically upgrade binary and .app
      version                   Print version information
    
    EXAMPLES:
      chargecap status
      sudo chargecap set 50
      sudo chargecap deadband on 3
      sudo chargecap install
      sudo chargecap update
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
    
    var governorMode = "Offline (Run 'sudo chargecap install')"
    if let liveJson = UnixSocketClient.send("STATUS"),
       let data = liveJson.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let gov = obj["governor"] as? [String: Any],
       let mode = gov["mode"] as? String {
        governorMode = mode
    }
    
    let isAC = status.isACConnected
    let chargingStr = status.isCharging ? "⚡ Charging" : (isAC ? "🔌 AC Connected (Not Charging)" : "🔋 Discharging")
    let wattageStr = String(format: "%.2fW", abs(status.wattageW))
    let healthBarLength = 20
    let filledHealth = Int((status.healthPercent / 100.0) * Double(healthBarLength))
    let bar = String(repeating: "█", count: max(0, min(healthBarLength, filledHealth))) +
              String(repeating: "░", count: max(0, healthBarLength - filledHealth))
    
    print("""
    ========================================================================
    ⚡ CHARGECAP POWER TELEMETRY & GOVERNOR
    ========================================================================
      Battery Level:      \(status.percent)% (\(chargingStr))
      Target Limit:       \(cfg.targetLimit)% \(cfg.deadbandEnabled ? "(Deadband -\(cfg.deadbandDelta)%)" : "(Strict)")
      Governor State:     \(governorMode)
      Health Condition:   [\(bar)] \(status.healthPercent)%
      Cycle Count:        \(status.cycleCount) cycles
      Voltage & Current:  \(status.voltageMV) mV  •  \(status.amperageMA) mA (\(wattageStr))
      Hardware Capacity:  \(status.fullChargeCapacityMAh) / \(status.designCapacityMAh) mAh
      Thermal State:      \(status.thermalState)
      Hardware Backend:   \(hw.modeName)
      Serial Number:      \(status.serialNumber)
    ========================================================================
    """)
    
    if let cachedData = UserDefaults.standard.data(forKey: "com.wixe.chargecap.cachedReleaseInfo"),
       let cached = try? JSONDecoder().decode(ReleaseInfo.self, from: cachedData),
       cached.isNewer {
        print("💡 Update available: \(cached.tagName) — Run 'sudo chargecap update' to upgrade.\n")
    }
}

func handleSet(args: [String]) {
    guard getuid() == 0 else {
        print("❌ Power control requires root privileges. Please run with sudo:\n   sudo chargecap set \(args.first ?? "50")")
        exit(1)
    }
    guard let first = args.first, let val = Int(first), val >= 30 && val <= 100 else {
        print("❌ Error: Please specify a valid limit between 30 and 100 (e.g. 'sudo chargecap set 50')")
        exit(1)
    }
    
    if let resp = UnixSocketClient.send("SET \(val)"), resp.contains("\"success\":true") {
        print("✅ ChargeCap daemon updated via socket: target limit is now \(val)%.")
        return
    }
    
    var cfg = ConfigManager.shared.load()
    cfg.targetLimit = val
    if ConfigManager.shared.save(cfg) {
        let hw = HardwareBackend()
        _ = hw.setChargeLimitPercentage(val, delta: cfg.deadbandEnabled ? cfg.deadbandDelta : 1)
        print("✅ Saved target charge limit: \(val)%")
    } else {
        print("⚠️ Warning: Could not write configuration. Try running with 'sudo'.")
    }
}

func handleDeadband(args: [String]) {
    guard getuid() == 0 else {
        print("❌ Power control requires root privileges. Please run with sudo:\n   sudo chargecap deadband \(args.joined(separator: " "))")
        exit(1)
    }
    guard let first = args.first?.lowercased() else {
        print("❌ Usage: sudo chargecap deadband <on|off> [delta_percent]")
        exit(1)
    }
    
    let enabled = (first == "on" || first == "true" || first == "1")
    var delta = 3
    if args.count > 1, let d = Int(args[1]), d >= 1 && d <= 10 {
        delta = d
    }
    
    if let resp = UnixSocketClient.send("DEADBAND \(enabled ? "on" : "off") \(delta)"), resp.contains("\"success\":true") {
        print("✅ Hysteresis deadband updated via socket: \(enabled ? "ENABLED (-\(delta)%)" : "DISABLED")")
        return
    }
    
    var cfg = ConfigManager.shared.load()
    cfg.deadbandEnabled = enabled
    cfg.deadbandDelta = delta
    if ConfigManager.shared.save(cfg) {
        print("✅ Hysteresis deadband updated: \(enabled ? "ENABLED (-\(delta)%)" : "DISABLED")")
    } else {
        print("⚠️ Warning: Could not write configuration. Try running with 'sudo'.")
    }
}

func handleDaemon() {
    print("🚀 Starting ChargeCap Governor Daemon...")
    let cfg = ConfigManager.shared.load()
    let governor = AIGovernor(config: cfg)
    governor.start()
    
    let server = UnixSocketServer(governor: governor)
    server.start()
    ipcServer = server
    print("🔌 ChargeCap Unix Socket listening at \(UnixSocketServer.defaultSocketPath)")
    
    // Register signal handler for clean shutdown
    signal(SIGINT) { _ in
        print("\n🛑 ChargeCap daemon terminating...")
        ipcServer?.stop()
        exit(0)
    }
    signal(SIGTERM) { _ in
        print("\n🛑 ChargeCap daemon terminating...")
        ipcServer?.stop()
        exit(0)
    }
    
    RunLoop.main.run()
}

func handleInstall() {
    guard getuid() == 0 else {
        print("❌ Installation requires root privileges. Please run:\n   sudo chargecap install")
        exit(1)
    }
    
    let binSource: String
    if FileManager.default.fileExists(atPath: "/usr/local/bin/chargecap") {
        binSource = "/usr/local/bin/chargecap"
    } else if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/chargecap") {
        binSource = "/opt/homebrew/bin/chargecap"
    } else {
        binSource = CommandLine.arguments[0]
    }
    
    let daemonDir = "/Library/Application Support/ChargeCap"
    let daemonBin = "\(daemonDir)/ChargeCapDaemon"
    try? FileManager.default.createDirectory(atPath: daemonDir, withIntermediateDirectories: true)
    
    // Copy binary as ChargeCapDaemon so macOS System Settings displays "ChargeCapDaemon"
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
    
    // Ensure /usr/local/bin/chargecap exists for terminal usage
    if !FileManager.default.fileExists(atPath: "/usr/local/bin/chargecap") {
        try? FileManager.default.createDirectory(atPath: "/usr/local/bin", withIntermediateDirectories: true)
        let cpCli = Process()
        cpCli.executableURL = URL(fileURLWithPath: "/bin/cp")
        cpCli.arguments = ["-f", daemonBin, "/usr/local/bin/chargecap"]
        try? cpCli.run()
        cpCli.waitUntilExit()
        
        let chmodCli = Process()
        chmodCli.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodCli.arguments = ["755", "/usr/local/bin/chargecap"]
        try? chmodCli.run()
        chmodCli.waitUntilExit()
        
        let codesignCli = Process()
        codesignCli.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesignCli.arguments = ["--force", "--sign", "-", "/usr/local/bin/chargecap"]
        try? codesignCli.run()
        codesignCli.waitUntilExit()
    }
    
    let plistContent = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.wixe.chargecap.daemon</string>
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
        <string>/var/log/chargecap.log</string>
        <key>StandardErrorPath</key>
        <string>/var/log/chargecap.error.log</string>
    </dict>
    </plist>
    """
    
    let oldPlistPath = "/Library/LaunchDaemons/com.wixe.chargecap.plist"
    let plistPath = "/Library/LaunchDaemons/com.wixe.chargecap.daemon.plist"
    
    // Bootout existing legacy or current label
    for label in ["com.wixe.chargecap", "com.wixe.chargecap.daemon"] {
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "system/\(label)"]
        try? bootout.run()
        bootout.waitUntilExit()
    }
    
    // Remove old legacy plist so macOS BTM removes the ghost "chargecap" entry
    try? FileManager.default.removeItem(atPath: oldPlistPath)
    
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
        kickstart.arguments = ["kickstart", "-k", "system/com.wixe.chargecap.daemon"]
        try? kickstart.run()
        kickstart.waitUntilExit()
        
        print("✅ ChargeCap LaunchDaemon installed and bootstrapped successfully!")
        print("   Daemon name: ChargeCapDaemon (\(daemonBin))")
        print("   CLI command: chargecap (/usr/local/bin/chargecap)")
        print("   Plist: \(plistPath)")
        print("   Logs:  /var/log/chargecap.log")
    } catch {
        print("❌ Failed to install LaunchDaemon: \(error.localizedDescription)")
        exit(1)
    }
}

func handleUninstall() {
    guard getuid() == 0 else {
        print("❌ Uninstallation requires root privileges. Please run:\n   sudo chargecap uninstall")
        exit(1)
    }
    
    for label in ["com.wixe.chargecap.daemon", "com.wixe.chargecap"] {
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "system/\(label)"]
        try? bootout.run()
        bootout.waitUntilExit()
    }
    
    try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.wixe.chargecap.daemon.plist")
    try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.wixe.chargecap.plist")
    try? FileManager.default.removeItem(atPath: "/Library/Application Support/ChargeCap")
    try? FileManager.default.removeItem(atPath: "/var/run/chargecap.sock")
    print("✅ ChargeCap LaunchDaemon uninstalled successfully.")
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
            print("✅ ChargeCap is already up to date! (v\(VERSION))")
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
            print("Run 'sudo chargecap update' to install.")
            return
        }
        
        guard getuid() == 0 else {
            print("❌ Root privileges required to install update. Please run:\n   sudo chargecap update")
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
            
            // If /Applications/ChargeCap.app exists, update it too
            if FileManager.default.fileExists(atPath: "/Applications/ChargeCap.app"),
               let dmgUrl = URL(string: info.dmgUrl) {
                print("🖥  Updating /Applications/ChargeCap.app...")
                try await UpdateChecker.installAppUpdate(dmgUrl: dmgUrl, relaunch: false) { step in
                    print("   → \(step)")
                }
            }
            
            print("✅ ChargeCap successfully updated to \(info.tagName)!")
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
case "deadband":
    handleDeadband(args: Array(args.dropFirst()))
case "daemon":
    handleDaemon()
case "install":
    handleInstall()
case "uninstall":
    handleUninstall()
case "update":
    handleUpdate(args: Array(args.dropFirst()))
case "version", "--version", "-v":
    print("ChargeCap version \(VERSION)")
case "help", "--help", "-h":
    printHelp()
default:
    print("Unknown command: '\(command)'")
    printHelp()
    exit(1)
}
