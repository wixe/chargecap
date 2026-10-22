import Foundation
import ChargeCapCore

let VERSION = "0.1.0"

func printHelp() {
    print("""
    ⚡ ChargeCap — Intelligent, Lightweight Battery & Power Management for macOS
    Version \(VERSION) (Apple Silicon & Intel)
    Website: https://github.com/wixe/chargecap
    
    USAGE:
      chargecap <command> [options]
    
    COMMANDS:
      status [--json]          Display battery health, power telemetry, and governor status
      set <limit>              Set target charge limit (e.g. 50, 80)
      sailing <on|off> [delta] Toggle micro-sailing hysteresis (e.g. sailing on 3)
      daemon                   Run the AI power management governor in the foreground
      install                  Install and bootstrap background LaunchDaemon (runs 24/7 as root)
      uninstall                Remove and unload background LaunchDaemon
      version                  Print version information
    
    EXAMPLES:
      chargecap status
      chargecap set 50
      chargecap sailing on 3
      sudo chargecap install
    """)
}

func handleStatus(jsonOutput: Bool) {
    let monitor = BatteryMonitor()
    let status = monitor.getCurrentStatus()
    let cfg = ConfigManager.shared.load()
    let hw = HardwareBackend()
    
    if jsonOutput {
        let governor = AIGovernor(config: cfg)
        let report = governor.getCombinedReport()
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        return
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
      Target Limit:       \(cfg.targetLimit)% \(cfg.sailingEnabled ? "(Micro-Sailing ±\(cfg.sailingDelta)%)" : "(Fixed)")
      Health Condition:   [\(bar)] \(status.healthPercent)%
      Cycle Count:        \(status.cycleCount) cycles
      Voltage & Current:  \(status.voltageMV) mV  •  \(status.amperageMA) mA (\(wattageStr))
      Hardware Capacity:  \(status.fullChargeCapacityMAh) / \(status.designCapacityMAh) mAh
      Thermal State:      \(status.thermalState)
      Hardware Backend:   \(hw.modeName)
      Serial Number:      \(status.serialNumber)
    ========================================================================
    """)
}

func handleSet(args: [String]) {
    guard let first = args.first, let val = Int(first), val >= 20 && val <= 100 else {
        print("❌ Error: Please specify a valid limit between 20 and 100 (e.g. 'chargecap set 50')")
        exit(1)
    }
    
    // Check if daemon is running via HTTP
    if let url = URL(string: "http://127.0.0.1:8772/api/set?limit=\(val)") {
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        let sema = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: req) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                print("✅ ChargeCap daemon updated: target limit is now \(val)%.")
            }
            sema.signal()
        }
        task.resume()
        _ = sema.wait(timeout: .now() + 1.2)
    }
    
    var cfg = ConfigManager.shared.load()
    cfg.targetLimit = val
    if ConfigManager.shared.save(cfg) {
        let hw = HardwareBackend()
        _ = hw.setChargeLimitPercentage(val)
        print("✅ Saved target charge limit: \(val)%")
    } else {
        print("⚠️ Warning: Could not write configuration. Try running with 'sudo'.")
    }
}

func handleSailing(args: [String]) {
    guard let first = args.first?.lowercased() else {
        print("❌ Usage: chargecap sailing <on|off> [delta_percent]")
        exit(1)
    }
    
    let enabled = (first == "on" || first == "true" || first == "1")
    var delta = 3
    if args.count > 1, let d = Int(args[1]), d >= 1 && d <= 10 {
        delta = d
    }
    
    var cfg = ConfigManager.shared.load()
    cfg.sailingEnabled = enabled
    cfg.sailingDelta = delta
    if ConfigManager.shared.save(cfg) {
        print("✅ Micro-sailing updated: \(enabled ? "ENABLED (±\(delta)%)" : "DISABLED")")
    } else {
        print("⚠️ Warning: Could not write configuration. Try running with 'sudo'.")
    }
}

func handleDaemon() {
    print("🚀 Starting ChargeCap Governor Daemon...")
    let cfg = ConfigManager.shared.load()
    let governor = AIGovernor(config: cfg)
    governor.start()
    
    var server: StatusServer? = nil
    if cfg.httpEnabled {
        server = StatusServer(port: cfg.httpPort, governor: governor)
        server?.start()
    }
    
    // Register signal handler for clean shutdown
    signal(SIGINT) { _ in
        print("\n🛑 ChargeCap daemon terminating...")
        exit(0)
    }
    signal(SIGTERM) { _ in
        print("\n🛑 ChargeCap daemon terminating...")
        exit(0)
    }
    
    RunLoop.main.run()
}

func handleInstall() {
    guard getuid() == 0 else {
        print("❌ Installation requires root privileges. Please run:\n   sudo chargecap install")
        exit(1)
    }
    
    let binPath: String
    if FileManager.default.fileExists(atPath: "/usr/local/bin/chargecap") {
        binPath = "/usr/local/bin/chargecap"
    } else if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/chargecap") {
        binPath = "/opt/homebrew/bin/chargecap"
    } else {
        // Fall back to current executable
        binPath = CommandLine.arguments[0]
    }
    
    let plistContent = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.wixe.chargecap</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(binPath)</string>
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
    
    let plistPath = "/Library/LaunchDaemons/com.wixe.chargecap.plist"
    do {
        try plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["644", plistPath]
        try? chmod.run()
        chmod.waitUntilExit()
        
        // Bootout existing if present
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "system/com.wixe.chargecap"]
        try? bootout.run()
        bootout.waitUntilExit()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Bootstrap new
        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", "system", plistPath]
        try? bootstrap.run()
        bootstrap.waitUntilExit()
        
        // Ensure running daemon is restarted with new binary
        let kickstart = Process()
        kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        kickstart.arguments = ["kickstart", "-k", "system/com.wixe.chargecap"]
        try? kickstart.run()
        kickstart.waitUntilExit()
        
        print("✅ ChargeCap LaunchDaemon installed and bootstrapped successfully!")
        print("   Daemon is running 24/7 as root: \(plistPath)")
        print("   Logs: /var/log/chargecap.log")
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
    
    let plistPath = "/Library/LaunchDaemons/com.wixe.chargecap.plist"
    let bootout = Process()
    bootout.launchPath = "/bin/launchctl"
    bootout.arguments = ["bootout", "system", plistPath]
    try? bootout.run()
    bootout.waitUntilExit()
    
    try? FileManager.default.removeItem(atPath: plistPath)
    print("✅ ChargeCap LaunchDaemon uninstalled successfully.")
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
case "sailing":
    handleSailing(args: Array(args.dropFirst()))
case "daemon":
    handleDaemon()
case "install":
    handleInstall()
case "uninstall":
    handleUninstall()
case "version", "--version", "-v":
    print("ChargeCap version \(VERSION)")
case "help", "--help", "-h":
    printHelp()
default:
    print("Unknown command: '\(command)'")
    printHelp()
    exit(1)
}
