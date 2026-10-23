import AppKit
import Foundation
import ChargePlanCore

final class BatteryGraphView: NSView {
    struct Sample {
        let percent: Double
        let targetLimit: Int
        let isCharging: Bool
    }
    
    private var samples: [Sample] = []
    private let maxSamples = 60
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    func addSample(percent: Double, targetLimit: Int, isCharging: Bool) {
        if samples.isEmpty {
            for _ in 0..<maxSamples {
                samples.append(Sample(percent: percent, targetLimit: targetLimit, isCharging: isCharging))
            }
        } else {
            samples.append(Sample(percent: percent, targetLimit: targetLimit, isCharging: isCharging))
            if samples.count > maxSamples {
                samples.removeFirst(samples.count - maxSamples)
            }
        }
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let rect = bounds
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.withAlphaComponent(0.6).setFill()
        bgPath.fill()
        NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()
        
        let padX: CGFloat = 8
        let padBottom: CGFloat = 16
        let padTop: CGFloat = 14
        let plotW = rect.width - padX * 2
        let plotH = rect.height - padBottom - padTop
        guard plotW > 10 && plotH > 10 else { return }
        
        // Grid reference lines (50%, 100%)
        let gridColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.3)
        let gridFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: gridFont,
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.7)
        ]
        
        for level in [50, 100] {
            let y = padBottom + (CGFloat(level) / 100.0) * plotH
            let gPath = NSBezierPath()
            gPath.move(to: NSPoint(x: padX, y: y))
            gPath.line(to: NSPoint(x: rect.width - padX, y: y))
            let dashes: [CGFloat] = [2, 4]
            gPath.setLineDash(dashes, count: 2, phase: 0)
            gridColor.setStroke()
            gPath.lineWidth = 0.5
            gPath.stroke()
            
            let label = "\(level)%"
            (label as NSString).draw(at: NSPoint(x: padX + 2, y: min(rect.height - 12, y - 4)), withAttributes: textAttrs)
        }
        
        // Target Limit dashed line (Amber / Orange)
        if let targetLimit = samples.last?.targetLimit, targetLimit > 0, targetLimit < 100 {
            let targetY = padBottom + (CGFloat(targetLimit) / 100.0) * plotH
            let tPath = NSBezierPath()
            tPath.move(to: NSPoint(x: padX, y: targetY))
            tPath.line(to: NSPoint(x: rect.width - padX, y: targetY))
            let dashes: [CGFloat] = [4, 3]
            tPath.setLineDash(dashes, count: 2, phase: 0)
            NSColor.systemOrange.withAlphaComponent(0.75).setStroke()
            tPath.lineWidth = 1.0
            tPath.stroke()
            
            let capTag = "Cap \(targetLimit)%"
            let capAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
                .foregroundColor: NSColor.systemOrange
            ]
            let tagSize = (capTag as NSString).size(withAttributes: capAttrs)
            (capTag as NSString).draw(at: NSPoint(x: rect.width - padX - tagSize.width - 2, y: min(rect.height - 12, targetY - 4)), withAttributes: capAttrs)
        }
        
        guard samples.count >= 2 else { return }
        
        var points: [NSPoint] = []
        for (i, s) in samples.enumerated() {
            let x = padX + (CGFloat(i) / CGFloat(samples.count - 1)) * plotW
            let clampedPct = max(0.0, min(100.0, s.percent))
            let y = padBottom + (CGFloat(clampedPct) / 100.0) * plotH
            points.append(NSPoint(x: x, y: y))
        }
        
        let isCharging = samples.last?.isCharging ?? false
        let baseColor = isCharging ? NSColor.systemGreen : NSColor.systemBlue
        
        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: points[0].x, y: padBottom))
        for pt in points {
            fillPath.line(to: pt)
        }
        fillPath.line(to: NSPoint(x: points.last!.x, y: padBottom))
        fillPath.close()
        
        ctx.saveGState()
        fillPath.addClip()
        let gradient = NSGradient(starting: baseColor.withAlphaComponent(0.28), ending: baseColor.withAlphaComponent(0.02))
        gradient?.draw(in: rect, angle: 90)
        ctx.restoreGState()
        
        let strokePath = NSBezierPath()
        strokePath.move(to: points[0])
        for pt in points.dropFirst() {
            strokePath.line(to: pt)
        }
        baseColor.setStroke()
        strokePath.lineWidth = 2.0
        strokePath.lineCapStyle = .round
        strokePath.lineJoinStyle = .round
        strokePath.stroke()
        
        if let lastPt = points.last, let lastSample = samples.last {
            baseColor.withAlphaComponent(0.3).setFill()
            let glow = NSBezierPath(ovalIn: NSRect(x: lastPt.x - 5, y: lastPt.y - 5, width: 10, height: 10))
            glow.fill()
            
            baseColor.setFill()
            let dot = NSBezierPath(ovalIn: NSRect(x: lastPt.x - 2.5, y: lastPt.y - 2.5, width: 5, height: 5))
            dot.fill()
            
            let str = String(format: "%.2f%%", lastSample.percent)
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                .foregroundColor: baseColor
            ]
            let strSize = (str as NSString).size(withAttributes: badgeAttrs)
            var strX = lastPt.x - strSize.width - 6
            var strY = lastPt.y + 4
            if strY + strSize.height > rect.height - 2 {
                strY = lastPt.y - strSize.height - 4
            }
            if strX < padX {
                strX = padX + 2
            }
            (str as NSString).draw(at: NSPoint(x: strX, y: strY), withAttributes: badgeAttrs)
        }
    }
}

@MainActor
final class ChargePlanAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var settingsWindow: NSWindow?
    
    // Settings window controls
    private var batteryLabel: NSTextField?
    private var governorLabel: NSTextField?
    private var telemetryLabel: NSTextField?
    private var daemonBadgeLabel: NSTextField?
    private var batteryGraphView: BatteryGraphView?
    private var limitSlider: NSSlider?
    private var limitValueLabel: NSTextField?
    private var driftCheckbox: NSButton?
    private var loginCheckbox: NSButton?
    private var installDaemonButton: NSButton?
    private var uninstallDaemonButton: NSButton?
    
    // Update state & controls
    private var latestRelease: ReleaseInfo?
    private var isUpdatingApp: Bool = false
    private var isAutoSyncingDaemon: Bool = false
    private var updateStatusText: String = ""
    private var updateBox: NSBox?
    private var updateLabel: NSTextField?
    private var updateSubLabel: NSTextField?
    private var updateActionButton: NSButton?
    
    private let monitor = BatteryMonitor()
    private lazy var fallbackHardware = HardwareBackend()
    private let launchAgentPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Clean up legacy LaunchAgent plist if present
        let legacyPath = "\(home)/Library/LaunchAgents/com.wixe.chargeplan.app.plist"
        if FileManager.default.fileExists(atPath: legacyPath) {
            _ = try? FileManager.default.removeItem(atPath: legacyPath)
        }
        return "\(home)/Library/LaunchAgents/io.github.wixe.chargeplan.app.plist"
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
        
        // Automatically ensure background daemon binary matches this app version
        autoSyncDaemonIfNeeded()
        
        // Background check for updates (cached 24h, 0 overhead)
        Task {
            await checkUpdateSilently()
        }
        
        // Show the Settings / Dashboard window if launched interactively (not via --background Login Agent)
        if !CommandLine.arguments.contains("--background") {
            showSettingsWindow()
        }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.autoSyncDaemonIfNeeded()
                self?.rebuildMenu()
                self?.refreshSettingsWindow()
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }
    
    private func fetchDaemonStatus() -> (running: Bool, mode: String, backend: String?, version: String?) {
        if let liveJson = UnixSocketClient.send("STATUS"),
           let data = liveJson.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gov = obj["governor"] as? [String: Any],
           let mode = gov["mode"] as? String {
            let backend = gov["backend"] as? String
            let version = gov["version"] as? String
            return (true, mode, backend, version)
        }
        return (false, "Daemon Not Installed", nil, nil)
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
        
        let titleItem = NSMenuItem(title: "⚡ ChargePlan Battery Governor", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        if let rel = latestRelease, UpdateChecker.isVersion(rel.version, newerThan: ChargePlanVersion) {
            let updateItem = NSMenuItem(title: "⬆️ Update Available (\(rel.tagName))…", action: #selector(triggerAppUpdate), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(.separator())
        } else {
            let latestItem = NSMenuItem(title: "✓ ChargePlan v\(ChargePlanVersion) (Latest)", action: nil, keyEquivalent: "")
            latestItem.isEnabled = false
            menu.addItem(latestItem)
            menu.addItem(.separator())
        }
        
        let stateStr = status.isCharging ? "Charging" : (status.isACConnected ? "AC Pass-Through (On Hold)" : "On Battery")
        let wattageStr = String(format: "%.1fW", abs(status.wattageW))
        let pctFormatted = String(format: "%.2f%%", status.exactPercent)
        batteryGraphView?.addSample(percent: status.exactPercent, targetLimit: cfg.targetLimit, isCharging: status.isCharging)
        
        let infoLines = [
            "Battery: \(pctFormatted) (\(stateStr))",
            "Target Cap: \(cfg.targetLimit)% \(cfg.driftEnabled ? "(Drift -\(cfg.driftMargin)%)" : "(Strict)")",
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
        
        // Drift Margin Submenu
        let driftMenu = NSMenu()
        for (enabled, margin, title) in [(true, 3, "Enabled (-3% Drift)"), (true, 5, "Enabled (-5% Drift)"), (false, 3, "Disabled (Strict Cap)")] {
            let dItem = NSMenuItem(title: title, action: #selector(selectDriftOption(_:)), keyEquivalent: "")
            dItem.target = self
            dItem.tag = enabled ? margin : 0
            dItem.state = (cfg.driftEnabled == enabled && (!enabled || cfg.driftMargin == margin)) ? .on : .off
            driftMenu.addItem(dItem)
        }
        let driftRoot = NSMenuItem(title: "Drift Margin", action: nil, keyEquivalent: "")
        driftRoot.submenu = driftMenu
        menu.addItem(driftRoot)
        
        // Status Icon Legend Submenu
        let legendMenu = NSMenu()
        let legendItems = [
            ("⚡", "Charging", "Cells actively accepting power to target"),
            ("🔌", "AC Pass-Through", "Wall power idle hold (0.00W battery stress)"),
            ("🔋", "On Battery", "Discharging, AC adapter disconnected")
        ]
        for (icon, title, desc) in legendItems {
            let item = NSMenuItem(title: "\(icon)  \(title) — \(desc)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            legendMenu.addItem(item)
        }
        let legendRoot = NSMenuItem(title: "Status Icon Legend", action: nil, keyEquivalent: "")
        legendRoot.submenu = legendMenu
        menu.addItem(legendRoot)
        
        menu.addItem(.separator())
        
        let kickItem = NSMenuItem(title: "⚡ Manual Power Latch Kick", action: #selector(triggerManualKick), keyEquivalent: "")
        kickItem.target = self
        menu.addItem(kickItem)
        
        let openSettingsItem = NSMenuItem(title: "Open ChargePlan Settings & Installer…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)
        
        let checkUpdateItem = NSMenuItem(title: "Check for Updates…", action: #selector(menuCheckForUpdates), keyEquivalent: "")
        checkUpdateItem.target = self
        menu.addItem(checkUpdateItem)
        
        let loginItem = NSMenuItem(title: "Start Menu Bar Icon at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(loginItem)
        
        if !daemonActive {
            let installItem = NSMenuItem(title: "⚠️ Enable Background Governor Daemon…", action: #selector(installDaemonAction), keyEquivalent: "")
            installItem.target = self
            menu.addItem(installItem)
        } else if !isDaemonBinaryUpToDate(runningDaemonVersion: daemonInfo.version) {
            let updateItem = NSMenuItem(title: "⚠️ Update Background Daemon…", action: #selector(installDaemonAction), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            let uninstallItem = NSMenuItem(title: "Uninstall Background Daemon…", action: #selector(uninstallDaemonAction), keyEquivalent: "")
            uninstallItem.target = self
            menu.addItem(uninstallItem)
        } else {
            let restartItem = NSMenuItem(title: "Restart Background Daemon", action: #selector(installDaemonAction), keyEquivalent: "")
            restartItem.target = self
            menu.addItem(restartItem)
            let uninstallItem = NSMenuItem(title: "Uninstall Background Daemon…", action: #selector(uninstallDaemonAction), keyEquivalent: "")
            uninstallItem.target = self
            menu.addItem(uninstallItem)
        }
        
        menu.addItem(.separator())
        
        let quitItem = NSMenuItem(title: "Quit ChargePlan Menu Bar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func showSettingsWindow() {
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 585),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "ChargePlan — Battery & Power Settings"
            win.center()
            win.isReleasedWhenClosed = false
            
            let content = NSView(frame: win.contentView!.bounds)
            win.contentView = content
            
            let title = NSTextField(labelWithString: "⚡ ChargePlan Power Governor")
            title.font = NSFont.boldSystemFont(ofSize: 18)
            title.frame = NSRect(x: 24, y: 538, width: 412, height: 26)
            content.addSubview(title)
            
            let daemonBadge = NSTextField(labelWithString: "")
            daemonBadge.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            daemonBadge.frame = NSRect(x: 24, y: 512, width: 412, height: 20)
            content.addSubview(daemonBadge)
            self.daemonBadgeLabel = daemonBadge
            
            let battBox = NSBox(frame: NSRect(x: 24, y: 416, width: 412, height: 90))
            battBox.title = "Live Battery & Governor Telemetry"
            content.addSubview(battBox)
            
            let bLabel = NSTextField(labelWithString: "")
            bLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
            bLabel.frame = NSRect(x: 12, y: 46, width: 380, height: 22)
            battBox.contentView?.addSubview(bLabel)
            self.batteryLabel = bLabel
            
            let gLabel = NSTextField(labelWithString: "")
            gLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            gLabel.frame = NSRect(x: 12, y: 25, width: 380, height: 18)
            battBox.contentView?.addSubview(gLabel)
            self.governorLabel = gLabel
            
            let tLabel = NSTextField(labelWithString: "")
            tLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            tLabel.textColor = .secondaryLabelColor
            tLabel.frame = NSRect(x: 12, y: 5, width: 380, height: 18)
            battBox.contentView?.addSubview(tLabel)
            self.telemetryLabel = tLabel
            
            let graphBox = NSBox(frame: NSRect(x: 24, y: 290, width: 412, height: 118))
            graphBox.title = "Live Battery & Charge Float Timeline"
            content.addSubview(graphBox)
            
            let gView = BatteryGraphView(frame: NSRect(x: 10, y: 24, width: 392, height: 70))
            graphBox.contentView?.addSubview(gView)
            self.batteryGraphView = gView
            
            let legendLabel = NSTextField(labelWithString: "Legend:  ⚡ Charging   •   🔌 AC Pass-Through (Wall Power)   •   🔋 On Battery")
            legendLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            legendLabel.textColor = .secondaryLabelColor
            legendLabel.alignment = .center
            legendLabel.frame = NSRect(x: 10, y: 4, width: 392, height: 16)
            graphBox.contentView?.addSubview(legendLabel)
            
            let cfg = ConfigManager.shared.load()
            
            let sliderTitle = NSTextField(labelWithString: "Target Charge Cap (30%–80% Longevity Range):")
            sliderTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            sliderTitle.frame = NSRect(x: 24, y: 256, width: 340, height: 20)
            content.addSubview(sliderTitle)
            
            let valLabel = NSTextField(labelWithString: "\(cfg.targetLimit)%")
            valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
            valLabel.frame = NSRect(x: 380, y: 256, width: 56, height: 20)
            valLabel.alignment = .right
            content.addSubview(valLabel)
            self.limitValueLabel = valLabel
            
            let slider = NSSlider(value: Double(max(30, min(100, cfg.targetLimit))), minValue: 30, maxValue: 100, target: self, action: #selector(sliderChanged(_:)))
            slider.frame = NSRect(x: 24, y: 228, width: 320, height: 24)
            slider.numberOfTickMarks = 15
            slider.allowsTickMarkValuesOnly = false
            content.addSubview(slider)
            self.limitSlider = slider
            
            let tierGuideLabel = NSTextField(labelWithString: "Min Safe: 30%   •   Optimal Mid: 50%   •   Max Health: 80%   •   Full: 100%")
            tierGuideLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            tierGuideLabel.textColor = .secondaryLabelColor
            tierGuideLabel.frame = NSRect(x: 24, y: 206, width: 412, height: 16)
            content.addSubview(tierGuideLabel)
            
            let applyBtn = NSButton(title: "Apply Limit", target: self, action: #selector(applySliderLimit))
            applyBtn.bezelStyle = .rounded
            applyBtn.frame = NSRect(x: 352, y: 226, width: 88, height: 28)
            content.addSubview(applyBtn)
            
            let driftCheck = NSButton(checkboxWithTitle: "Enable Drift Margin (-3% window — prevents micro-charge cycling)", target: self, action: #selector(toggleDriftCheckbox(_:)))
            driftCheck.state = cfg.driftEnabled ? .on : .off
            driftCheck.frame = NSRect(x: 24, y: 176, width: 416, height: 22)
            content.addSubview(driftCheck)
            self.driftCheckbox = driftCheck
            
            let loginCheck = NSButton(checkboxWithTitle: "Show ChargePlan icon in macOS Menu Bar automatically at login", target: self, action: #selector(toggleLaunchAtLogin))
            loginCheck.state = isLaunchAtLoginEnabled() ? .on : .off
            loginCheck.frame = NSRect(x: 24, y: 150, width: 416, height: 22)
            content.addSubview(loginCheck)
            self.loginCheckbox = loginCheck
            
            // Software Updates Box
            let uBox = NSBox(frame: NSRect(x: 24, y: 64, width: 412, height: 74))
            uBox.title = "Software Updates & Version"
            content.addSubview(uBox)
            self.updateBox = uBox
            
            let uLabel = NSTextField(labelWithString: "ChargePlan v\(ChargePlanVersion)")
            uLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            uLabel.frame = NSRect(x: 12, y: 30, width: 265, height: 20)
            uBox.contentView?.addSubview(uLabel)
            self.updateLabel = uLabel
            
            let uSub = NSTextField(labelWithString: "You are on the latest version.")
            uSub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            uSub.textColor = .secondaryLabelColor
            uSub.frame = NSRect(x: 12, y: 8, width: 265, height: 18)
            uBox.contentView?.addSubview(uSub)
            self.updateSubLabel = uSub
            
            let uBtn = NSButton(title: "Check Updates", target: self, action: #selector(updateActionButtonClicked))
            uBtn.bezelStyle = .rounded
            uBtn.frame = NSRect(x: 285, y: 12, width: 115, height: 32)
            uBox.contentView?.addSubview(uBtn)
            self.updateActionButton = uBtn
            
            let installBtn = NSButton(title: "Install / Update Background Daemon", target: self, action: #selector(installDaemonAction))
            installBtn.bezelStyle = .rounded
            installBtn.frame = NSRect(x: 24, y: 18, width: 235, height: 32)
            content.addSubview(installBtn)
            self.installDaemonButton = installBtn
            
            let uninstallBtn = NSButton(title: "Uninstall Daemon", target: self, action: #selector(uninstallDaemonAction))
            uninstallBtn.bezelStyle = .rounded
            uninstallBtn.frame = NSRect(x: 270, y: 18, width: 166, height: 32)
            content.addSubview(uninstallBtn)
            self.uninstallDaemonButton = uninstallBtn
            
            self.settingsWindow = win
        }
        
        refreshSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func isDaemonBinaryUpToDate(runningDaemonVersion: String? = nil) -> Bool {
        if let runningVer = runningDaemonVersion {
            return UpdateChecker.compareVersion(runningVer, ChargePlanVersion) != .orderedAscending
        }
        
        let installed = FileManager.default.fileExists(atPath: "/Library/Application Support/ChargePlan/ChargePlanDaemon")
            ? "/Library/Application Support/ChargePlan/ChargePlanDaemon"
            : "/usr/local/bin/chargeplan"
        guard FileManager.default.isExecutableFile(atPath: installed) else {
            return false
        }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: installed)
        proc.arguments = ["version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8) {
                let parts = str.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
                if let ver = parts.last {
                    return UpdateChecker.compareVersion(ver, ChargePlanVersion) != .orderedAscending
                }
            }
        } catch {
            return false
        }
        return false
    }
    
    private func autoSyncDaemonIfNeeded() {
        guard !isAutoSyncingDaemon else { return }
        let daemonInfo = fetchDaemonStatus()
        guard daemonInfo.running else { return }
        let upToDate = isDaemonBinaryUpToDate(runningDaemonVersion: daemonInfo.version)
        guard !upToDate else { return }
        
        isAutoSyncingDaemon = true
        let bundled = bundledCLIBinaryPath()
        
        Task {
            // 1. Try seamless zero-password socket UPGRADE first
            if let resp = UnixSocketClient.send("UPGRADE \(bundled)"), resp.contains("\"success\":true") {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run {
                    self.isAutoSyncingDaemon = false
                    self.rebuildMenu()
                    self.refreshSettingsWindow()
                }
                return
            }
            
            // 2. Fallback to privileged install if older running daemon does not support socket UPGRADE
            await MainActor.run {
                self.installDaemonAction()
                self.isAutoSyncingDaemon = false
            }
        }
    }
    
    private func refreshSettingsWindow() {
        guard settingsWindow != nil else { return }
        let status = monitor.getCurrentStatus()
        let cfg = ConfigManager.shared.load()
        let daemonInfo = fetchDaemonStatus()
        let daemonActive = daemonInfo.running
        let upToDate = isDaemonBinaryUpToDate(runningDaemonVersion: daemonInfo.version)
        let govMode = daemonInfo.mode
        
        if daemonActive && upToDate {
            daemonBadgeLabel?.stringValue = "✅ Background Daemon Active & Up-to-Date (/var/run/chargeplan.sock)"
            daemonBadgeLabel?.textColor = .systemGreen
            installDaemonButton?.title = "Reinstall / Restart Daemon"
        } else if daemonActive && !upToDate {
            if isAutoSyncingDaemon {
                daemonBadgeLabel?.stringValue = "⚡ Automatically Updating Background Daemon…"
                daemonBadgeLabel?.textColor = .systemBlue
                installDaemonButton?.title = "Updating Daemon…"
            } else {
                daemonBadgeLabel?.stringValue = "⚠️ Daemon Update Available — Auto-updating…"
                daemonBadgeLabel?.textColor = .systemOrange
                installDaemonButton?.title = "Update Background Daemon"
            }
        } else {
            daemonBadgeLabel?.stringValue = "⚠️ Background Daemon Not Running — Click 'Install Background Daemon' below"
            daemonBadgeLabel?.textColor = .systemOrange
            installDaemonButton?.title = "Install Background Daemon"
        }
        
        let stateStr = status.isCharging ? "⚡ Charging" : (status.isACConnected ? "🔌 AC Connected (Not Charging)" : "🔋 On Battery")
        let pctStr = String(format: "%.2f%%", status.exactPercent)
        batteryLabel?.stringValue = "Battery: \(pctStr) (\(stateStr))  •  Cap: \(cfg.targetLimit)%"
        governorLabel?.stringValue = "Governor State: \(govMode)"
        let capText = status.remainingCapacityMAh > 0 ? "Capacity: \(status.remainingCapacityMAh) / \(status.fullChargeCapacityMAh) mAh • " : ""
        telemetryLabel?.stringValue = String(format: "%.2fW (%d mV, %d mA) • %@Health: %.1f%% (%d cycles) • %@", abs(status.wattageW), status.voltageMV, status.amperageMA, capText, status.healthPercent, status.cycleCount, status.thermalState)
        batteryGraphView?.addSample(percent: status.exactPercent, targetLimit: cfg.targetLimit, isCharging: status.isCharging)
        
        driftCheckbox?.state = cfg.driftEnabled ? .on : .off
        loginCheckbox?.state = isLaunchAtLoginEnabled() ? .on : .off
        uninstallDaemonButton?.isEnabled = daemonActive
        
        // Update software updates section
        if isUpdatingApp {
            updateLabel?.stringValue = "⚡ Updating ChargePlan…"
            updateLabel?.textColor = .systemBlue
            updateSubLabel?.stringValue = updateStatusText
            updateActionButton?.title = "Updating…"
            updateActionButton?.isEnabled = false
        } else if let rel = latestRelease, UpdateChecker.isVersion(rel.version, newerThan: ChargePlanVersion) {
            updateLabel?.stringValue = "🎉 Update Available: \(rel.tagName)"
            updateLabel?.textColor = .systemOrange
            updateSubLabel?.stringValue = updateStatusText.isEmpty ? "New version ready to install." : updateStatusText
            updateActionButton?.title = "Update Now"
            updateActionButton?.isEnabled = true
        } else {
            updateLabel?.stringValue = "✓ ChargePlan v\(ChargePlanVersion) (Latest)"
            updateLabel?.textColor = .systemGreen
            updateSubLabel?.stringValue = updateStatusText.isEmpty ? "Up to date (Checked automatically)." : updateStatusText
            updateActionButton?.title = "Check Updates"
            updateActionButton?.isEnabled = true
        }
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
    
    @objc private func selectDriftOption(_ sender: NSMenuItem) {
        let margin = sender.tag
        let cmd = margin > 0 ? "DRIFT on \(margin)" : "DRIFT off"
        if let resp = UnixSocketClient.send(cmd), resp.contains("\"success\":true") {
            rebuildMenu()
            refreshSettingsWindow()
            return
        }
        if margin > 0 {
            runPrivilegedCLI("drift on \(margin)")
        } else {
            runPrivilegedCLI("drift off")
        }
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    @objc private func triggerManualKick() {
        if let resp = UnixSocketClient.send("KICK"), resp.contains("\"success\":true") {
            rebuildMenu()
            refreshSettingsWindow()
            return
        }
        fallbackHardware.kickPowerUIRefresh()
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    @objc private func toggleDriftCheckbox(_ sender: NSButton) {
        let on = (sender.state == .on)
        let cmd = "DRIFT \(on ? "on 3" : "off")"
        if let resp = UnixSocketClient.send(cmd), resp.contains("\"success\":true") {
            rebuildMenu()
            refreshSettingsWindow()
            return
        }
        runPrivilegedCLI(cmd.lowercased())
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    private func applyLimitWithAdminPrompt(_ limit: Int) {
        if let resp = UnixSocketClient.send("SET \(limit)"), resp.contains("\"success\":true") {
            rebuildMenu()
            refreshSettingsWindow()
            return
        }
        runPrivilegedCLI("set \(limit)")
        rebuildMenu()
        refreshSettingsWindow()
    }
    
    private func bundledCLIBinaryPath() -> String {
        if let resPath = Bundle.main.resourcePath {
            let candidate = "\(resPath)/chargeplan"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/chargeplan") {
            return "/usr/local/bin/chargeplan"
        }
        return "/usr/local/bin/chargeplan"
    }
    
    private func runPrivilegedCLI(_ subcommand: String) {
        let cliPath = FileManager.default.isExecutableFile(atPath: "/usr/local/bin/chargeplan")
            ? "/usr/local/bin/chargeplan"
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
        let cmd = "mkdir -p /usr/local/bin '/Library/Application Support/ChargePlan' && install -m 755 '\(bundled)' '/Library/Application Support/ChargePlan/ChargePlanDaemon' && install -m 755 '\(bundled)' /usr/local/bin/chargeplan && xattr -cr '/Library/Application Support/ChargePlan/ChargePlanDaemon' /usr/local/bin/chargeplan 2>/dev/null || true && codesign --force --sign - '/Library/Application Support/ChargePlan/ChargePlanDaemon' /usr/local/bin/chargeplan 2>/dev/null || true && /usr/local/bin/chargeplan install"
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
        let cmd = "/usr/local/bin/chargeplan uninstall && rm -rf '/Library/Application Support/ChargePlan' '/Library/Application Support/ChargeCap' /usr/local/bin/chargeplan /var/run/chargeplan.sock /var/run/chargecap.sock"
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
            let execPath = Bundle.main.executablePath ?? "/Applications/ChargePlan.app/Contents/MacOS/ChargePlanApp"
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>io.github.wixe.chargeplan.app</string>
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
    
    private func checkUpdateSilently(force: Bool = false) async {
        if let info = await UpdateChecker.checkForUpdate(currentVersion: ChargePlanVersion, force: force) {
            await MainActor.run {
                self.latestRelease = info
                self.rebuildMenu()
                self.refreshSettingsWindow()
            }
        }
    }
    
    @objc private func updateActionButtonClicked() {
        if let release = latestRelease, UpdateChecker.isVersion(release.version, newerThan: ChargePlanVersion) {
            triggerAppUpdate()
        } else {
            manualCheckUpdate()
        }
    }
    
    @objc private func triggerAppUpdate() {
        showSettingsWindow()
        guard let release = latestRelease, UpdateChecker.isVersion(release.version, newerThan: ChargePlanVersion) else { return }
        guard let dmgUrl = URL(string: release.dmgUrl) else { return }
        
        isUpdatingApp = true
        updateStatusText = "Downloading update disk image…"
        refreshSettingsWindow()
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await UpdateChecker.installAppUpdate(dmgUrl: dmgUrl, relaunch: true) { [weak self] step in
                    Task { @MainActor in
                        self?.updateStatusText = step
                        self?.refreshSettingsWindow()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isUpdatingApp = false
                    self.updateStatusText = "Update failed: \(error.localizedDescription)"
                    self.refreshSettingsWindow()
                }
            }
        }
    }
    
    @objc private func menuCheckForUpdates() {
        manualCheckUpdate(showAlertIfUpToDate: true)
    }
    
    @objc private func manualCheckUpdate() {
        manualCheckUpdate(showAlertIfUpToDate: true)
    }
    
    private func manualCheckUpdate(showAlertIfUpToDate: Bool = false) {
        updateStatusText = "Checking GitHub…"
        updateActionButton?.isEnabled = false
        refreshSettingsWindow()
        Task {
            let info = await UpdateChecker.checkForUpdate(currentVersion: ChargePlanVersion, force: true)
            await MainActor.run {
                self.latestRelease = info
                self.updateActionButton?.isEnabled = true
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let timeStr = formatter.string(from: Date())
                
                if let inf = info, UpdateChecker.isVersion(inf.version, newerThan: ChargePlanVersion) {
                    self.updateStatusText = "New release found: \(inf.tagName)"
                    self.rebuildMenu()
                    self.refreshSettingsWindow()
                    self.showSettingsWindow()
                } else {
                    self.updateStatusText = "✓ Up to date (checked at \(timeStr))"
                    self.rebuildMenu()
                    self.refreshSettingsWindow()
                    if showAlertIfUpToDate {
                        let alert = NSAlert()
                        alert.messageText = "ChargePlan is Up to Date"
                        alert.informativeText = "Version \(ChargePlanVersion) is currently the newest version available."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { ChargePlanAppDelegate() }
app.delegate = delegate
app.run()
