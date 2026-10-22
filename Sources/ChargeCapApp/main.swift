import AppKit
import Foundation
import ChargeCapCore

@MainActor
final class ChargeCapAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var settingsWindow: NSWindow?
    
    // Settings window controls
    private var batteryLabel: NSTextField?
    private var governorLabel: NSTextField?
    private var telemetryLabel: NSTextField?
    private var daemonBadgeLabel: NSTextField?
    private var limitSlider: NSSlider?
    private var limitValueLabel: NSTextField?
    private var deadbandCheckbox: NSButton?
    private var loginCheckbox: NSButton?
    private var installDaemonButton: NSButton?
    private var uninstallDaemonButton: NSButton?
    
    private let monitor = BatteryMonitor()
    private lazy var fallbackHardware = HardwareBackend()
    private let launchAgentPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/com.wixe.chargecap.app.plist"
    }()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⚡ --%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        
        // Enable Launch at Login by default on first run if installed in /Applications
        if Bundle.main.bundlePath.hasPrefix("/Applications") && !FileManager.default.fileExists(atPath: launchAgentPath) {
            setLaunchAtLogin(true)
        }
        
        rebuildMenu()
        
        // Show the Settings / Dashboard window if launched interactively (not via --background Login Agent)
        if !CommandLine.arguments.contains("--background") {
            showSettingsWindow()
        }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildMenu()
                self?.refreshSettingsWindow()
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }
    
    private func fetchDaemonStatus() -> (running: Bool, mode: String, backend: String?) {
        if let liveJson = UnixSocketClient.send("STATUS"),
           let data = liveJson.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gov = obj["governor"] as? [String: Any],
           let mode = gov["mode"] as? String {
            let backend = gov["backend"] as? String
            return (true, mode, backend)
        }
        return (false, "Daemon Not Installed", nil)
    }
    
    private func rebuildMenu() {
        let status = monitor.getCurrentStatus()
        let cfg = ConfigManager.shared.load()
        let daemonInfo = fetchDaemonStatus()
        let daemonActive = daemonInfo.running
        let govMode = daemonInfo.mode
        let backendName = daemonInfo.backend ?? fallbackHardware.modeName
        
        let iconPrefix = status.isCharging ? "⚡" : (status.isACConnected ? "🔌" : "🔋")
        statusItem.button?.title = "\(iconPrefix) \(status.percent)% → \(cfg.targetLimit)%"
        
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "⚡ ChargeCap Battery Governor", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        let stateStr = status.isCharging ? "Charging" : (status.isACConnected ? "AC Pass-Through (On Hold)" : "On Battery")
        let wattageStr = String(format: "%.1fW", abs(status.wattageW))
        
        let infoLines = [
            "Battery: \(status.percent)% (\(stateStr))",
            "Target Cap: \(cfg.targetLimit)% \(cfg.deadbandEnabled ? "(Deadband -\(cfg.deadbandDelta)%)" : "(Strict)")",
            "Governor: \(govMode)",
            "Power: \(wattageStr) • \(status.voltageMV) mV • \(status.amperageMA) mA",
            "Health: \(status.healthPercent)% (\(status.cycleCount) cycles) • \(status.thermalState)",
            "Backend: \(backendName)"
        ]
        for line in infoLines {
            let item = NSMenuItem(title: "  " + line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        
        menu.addItem(.separator())
        
        // Quick Presets
        let headerPresets = NSMenuItem(title: "Longevity Charge Cap Presets", action: nil, keyEquivalent: "")
        headerPresets.isEnabled = false
        menu.addItem(headerPresets)
        
        let presets: [(Int, String)] = [
            (30, "30% — Minimum Safe Floor (Low-Voltage Hold)"),
            (40, "40% — Cold Storage / Standby Cap"),
            (50, "50% — Optimal Mid Sweet Spot (24/7 Server / Clamshell)"),
            (60, "60% — Desk / Docked Cap"),
            (70, "70% — Hybrid Desk & Portable Cap"),
            (80, "80% — Maximum Longevity Cap (Daily Laptop)"),
            (100, "100% — Full Charge (Bypass Cap)")
        ]
        for (limit, label) in presets {
            let item = NSMenuItem(title: label, action: #selector(selectPresetLimit(_:)), keyEquivalent: "")
            item.target = self
            item.tag = limit
            item.state = (cfg.targetLimit == limit) ? .on : .off
            menu.addItem(item)
        }
        
        menu.addItem(.separator())
        
        // Hysteresis Deadband Submenu
        let deadbandMenu = NSMenu()
        for (enabled, delta, title) in [(true, 3, "Enabled (-3% Deadband)"), (true, 5, "Enabled (-5% Deadband)"), (false, 3, "Disabled (Strict Cap)")] {
            let dItem = NSMenuItem(title: title, action: #selector(selectDeadbandOption(_:)), keyEquivalent: "")
            dItem.target = self
            dItem.tag = enabled ? delta : 0
            dItem.state = (cfg.deadbandEnabled == enabled && (!enabled || cfg.deadbandDelta == delta)) ? .on : .off
            deadbandMenu.addItem(dItem)
        }
        let deadbandRoot = NSMenuItem(title: "Hysteresis Deadband", action: nil, keyEquivalent: "")
        deadbandRoot.submenu = deadbandMenu
        menu.addItem(deadbandRoot)
        
        menu.addItem(.separator())
        
        let openSettingsItem = NSMenuItem(title: "Open ChargeCap Settings & Installer…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)
        
        let loginItem = NSMenuItem(title: "Start Menu Bar Icon at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(loginItem)
        
        if !daemonActive {
            let installItem = NSMenuItem(title: "⚠️ Enable Background Governor Daemon…", action: #selector(installDaemonAction), keyEquivalent: "")
            installItem.target = self
            menu.addItem(installItem)
        } else {
            let updateItem = NSMenuItem(title: "Update / Restart Background Daemon…", action: #selector(installDaemonAction), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            let uninstallItem = NSMenuItem(title: "Uninstall Background Daemon…", action: #selector(uninstallDaemonAction), keyEquivalent: "")
            uninstallItem.target = self
            menu.addItem(uninstallItem)
        }
        
        menu.addItem(.separator())
        
        let quitItem = NSMenuItem(title: "Quit ChargeCap Menu Bar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func showSettingsWindow() {
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 405),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "ChargeCap — Battery & Power Settings"
            win.center()
            win.isReleasedWhenClosed = false
            
            let content = NSView(frame: win.contentView!.bounds)
            win.contentView = content
            
            let title = NSTextField(labelWithString: "⚡ ChargeCap Power Governor")
            title.font = NSFont.boldSystemFont(ofSize: 18)
            title.frame = NSRect(x: 24, y: 355, width: 412, height: 26)
            content.addSubview(title)
            
            let daemonBadge = NSTextField(labelWithString: "")
            daemonBadge.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            daemonBadge.frame = NSRect(x: 24, y: 329, width: 412, height: 20)
            content.addSubview(daemonBadge)
            self.daemonBadgeLabel = daemonBadge
            
            let battBox = NSBox(frame: NSRect(x: 24, y: 220, width: 412, height: 100))
            battBox.title = "Live Battery & Governor Telemetry"
            content.addSubview(battBox)
            
            let bLabel = NSTextField(labelWithString: "")
            bLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
            bLabel.frame = NSRect(x: 12, y: 52, width: 380, height: 22)
            battBox.contentView?.addSubview(bLabel)
            self.batteryLabel = bLabel
            
            let gLabel = NSTextField(labelWithString: "")
            gLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            gLabel.frame = NSRect(x: 12, y: 30, width: 380, height: 18)
            battBox.contentView?.addSubview(gLabel)
            self.governorLabel = gLabel
            
            let tLabel = NSTextField(labelWithString: "")
            tLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            tLabel.textColor = .secondaryLabelColor
            tLabel.frame = NSRect(x: 12, y: 8, width: 380, height: 18)
            battBox.contentView?.addSubview(tLabel)
            self.telemetryLabel = tLabel
            
            let cfg = ConfigManager.shared.load()
            
            let sliderTitle = NSTextField(labelWithString: "Target Charge Cap (30%–80% Longevity Range):")
            sliderTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            sliderTitle.frame = NSRect(x: 24, y: 178, width: 340, height: 20)
            content.addSubview(sliderTitle)
            
            let valLabel = NSTextField(labelWithString: "\(cfg.targetLimit)%")
            valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
            valLabel.frame = NSRect(x: 380, y: 178, width: 56, height: 20)
            valLabel.alignment = .right
            content.addSubview(valLabel)
            self.limitValueLabel = valLabel
            
            let slider = NSSlider(value: Double(max(30, min(100, cfg.targetLimit))), minValue: 30, maxValue: 100, target: self, action: #selector(sliderChanged(_:)))
            slider.frame = NSRect(x: 24, y: 150, width: 320, height: 24)
            slider.numberOfTickMarks = 15
            slider.allowsTickMarkValuesOnly = false
            content.addSubview(slider)
            self.limitSlider = slider
            
            let tierGuideLabel = NSTextField(labelWithString: "Min Safe: 30%   •   Optimal Mid: 50%   •   Max Health: 80%   •   Full: 100%")
            tierGuideLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            tierGuideLabel.textColor = .secondaryLabelColor
            tierGuideLabel.frame = NSRect(x: 24, y: 130, width: 412, height: 16)
            content.addSubview(tierGuideLabel)
            
            let applyBtn = NSButton(title: "Apply Limit", target: self, action: #selector(applySliderLimit))
            applyBtn.bezelStyle = .rounded
            applyBtn.frame = NSRect(x: 352, y: 148, width: 88, height: 28)
            content.addSubview(applyBtn)
            
            let deadbandCheck = NSButton(checkboxWithTitle: "Enable Hysteresis Deadband (-3% window — prevents micro-charge cycling)", target: self, action: #selector(toggleDeadbandCheckbox(_:)))
            deadbandCheck.state = cfg.deadbandEnabled ? .on : .off
            deadbandCheck.frame = NSRect(x: 24, y: 98, width: 416, height: 22)
            content.addSubview(deadbandCheck)
            self.deadbandCheckbox = deadbandCheck
            
            let loginCheck = NSButton(checkboxWithTitle: "Show ChargeCap icon in macOS Menu Bar automatically at login", target: self, action: #selector(toggleLaunchAtLogin))
            loginCheck.state = isLaunchAtLoginEnabled() ? .on : .off
            loginCheck.frame = NSRect(x: 24, y: 70, width: 416, height: 22)
            content.addSubview(loginCheck)
            self.loginCheckbox = loginCheck
            
            let installBtn = NSButton(title: "Install / Update Background Daemon", target: self, action: #selector(installDaemonAction))
            installBtn.bezelStyle = .rounded
            installBtn.frame = NSRect(x: 24, y: 20, width: 235, height: 32)
            content.addSubview(installBtn)
            self.installDaemonButton = installBtn
            
            let uninstallBtn = NSButton(title: "Uninstall Daemon", target: self, action: #selector(uninstallDaemonAction))
            uninstallBtn.bezelStyle = .rounded
            uninstallBtn.frame = NSRect(x: 270, y: 20, width: 166, height: 32)
            content.addSubview(uninstallBtn)
            self.uninstallDaemonButton = uninstallBtn
            
            self.settingsWindow = win
        }
        
        refreshSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func refreshSettingsWindow() {
        guard settingsWindow != nil else { return }
        let status = monitor.getCurrentStatus()
        let cfg = ConfigManager.shared.load()
        let daemonInfo = fetchDaemonStatus()
        let daemonActive = daemonInfo.running
        let govMode = daemonInfo.mode
        
        daemonBadgeLabel?.stringValue = daemonActive
            ? "✅ Background Daemon Active (/var/run/chargecap.sock)"
            : "⚠️ Background Daemon Not Running — Click 'Install / Update Background Daemon' below"
        daemonBadgeLabel?.textColor = daemonActive ? .systemGreen : .systemOrange
        
        let stateStr = status.isCharging ? "⚡ Charging" : (status.isACConnected ? "🔌 AC Connected (Not Charging)" : "🔋 On Battery")
        batteryLabel?.stringValue = "Battery: \(status.percent)% (\(stateStr))  •  Cap: \(cfg.targetLimit)%"
        governorLabel?.stringValue = "Governor State: \(govMode)"
        telemetryLabel?.stringValue = String(format: "%.2fW (%d mV, %d mA) • Health: %.1f%% (%d cycles) • Thermal: %@", abs(status.wattageW), status.voltageMV, status.amperageMA, status.healthPercent, status.cycleCount, status.thermalState)
        
        deadbandCheckbox?.state = cfg.deadbandEnabled ? .on : .off
        loginCheckbox?.state = isLaunchAtLoginEnabled() ? .on : .off
        uninstallDaemonButton?.isEnabled = daemonActive
    }
    
    @objc private func sliderChanged(_ sender: NSSlider) {
        let rounded = Int((sender.doubleValue / 5.0).rounded()) * 5
        let clamped = max(30, min(100, rounded))
        sender.integerValue = clamped
        limitValueLabel?.stringValue = "\(clamped)%"
    }
    
    @objc private func applySliderLimit() {
        let val = limitSlider?.integerValue ?? 50
        applyLimitWithAdminPrompt(val)
    }
    
    @objc private func selectPresetLimit(_ sender: NSMenuItem) {
        let val = sender.tag
        limitSlider?.integerValue = val
        limitValueLabel?.stringValue = "\(val)%"
        applyLimitWithAdminPrompt(val)
    }
    
    @objc private func selectDeadbandOption(_ sender: NSMenuItem) {
        let delta = sender.tag
        if delta > 0 {
            runPrivilegedCLI("deadband on \(delta)")
        } else {
            runPrivilegedCLI("deadband off")
        }
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    @objc private func toggleDeadbandCheckbox(_ sender: NSButton) {
        let on = (sender.state == .on)
        runPrivilegedCLI("deadband \(on ? "on 3" : "off")")
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    private func applyLimitWithAdminPrompt(_ limit: Int) {
        runPrivilegedCLI("set \(limit)")
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    private func bundledCLIBinaryPath() -> String {
        if let resPath = Bundle.main.resourcePath {
            let candidate = "\(resPath)/chargecap"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/chargecap") {
            return "/usr/local/bin/chargecap"
        }
        return "/usr/local/bin/chargecap"
    }
    
    private func runPrivilegedCLI(_ subcommand: String) {
        let cliPath = FileManager.default.isExecutableFile(atPath: "/usr/local/bin/chargecap")
            ? "/usr/local/bin/chargecap"
            : bundledCLIBinaryPath()
        let script = "do shell script \"'\(cliPath)' \(subcommand)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
        proc.waitUntilExit()
    }
    
    @objc private func installDaemonAction() {
        let bundled = bundledCLIBinaryPath()
        let cmd = "mkdir -p /usr/local/bin && rm -f /usr/local/bin/chargecap && install -m 755 '\(bundled)' /usr/local/bin/chargecap && xattr -cr /usr/local/bin/chargecap 2>/dev/null || true && codesign --force --sign - /usr/local/bin/chargecap 2>/dev/null || true && /usr/local/bin/chargecap install"
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
        proc.waitUntilExit()
        
        Thread.sleep(forTimeInterval: 0.5)
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    @objc private func uninstallDaemonAction() {
        let cmd = "/usr/local/bin/chargecap uninstall && rm -f /usr/local/bin/chargecap /var/run/chargecap.sock"
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
        proc.waitUntilExit()
        
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    private func isLaunchAtLoginEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentPath)
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        let fm = FileManager.default
        if enabled {
            let parent = (launchAgentPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            let execPath = Bundle.main.executablePath ?? "/Applications/ChargeCap.app/Contents/MacOS/ChargeCapApp"
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.wixe.chargecap.app</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                    <string>--background</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            try? plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        } else {
            try? fm.removeItem(atPath: launchAgentPath)
        }
    }
    
    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled())
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { ChargeCapAppDelegate() }
app.delegate = delegate
app.run()
