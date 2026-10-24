import Foundation
import Darwin
import ObjectiveC
import OSLog

public enum ChargingMode: Equatable {
    case directSMC
    case nativePowerUI
    case auxiliaryCLI(path: String)
    case simulation
}

public class HardwareBackend {
    private var smcDriver: SMCDriver?
    private var activeMode: ChargingMode = .simulation
    private var currentLimit: Int = 50
    private var currentDelta: Int = 3
    private let logger = Logger(subsystem: "io.github.wixe.chargeplan", category: "HardwareBackend")
    
    // Cached PowerUISmartChargeClient instance
    private var powerUIClient: AnyObject?
    private var powerUIClass: NSObject.Type?
    private var powerUIAvailableLimits: [Int] = []
    private var lastPublishedLimit: Int = -1
    private var lastPublishAt: Date = .distantPast
    private var powerdCache: (at: Date, value: Int?, explicitNone: Bool)?
    private let powerdLock = NSLock()
    
    public init() {
        self.smcDriver = SMCDriver()
        self.setupPowerUI()
        self.activeMode = detectBestMode()
    }
    
    private func setupPowerUI() {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else {
            return
        }
        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("initWithClientName:")
        guard cls.responds(to: allocSel) else { return }
        let rawObj = cls.perform(allocSel).takeUnretainedValue()
        guard rawObj.responds(to: initSel) else { return }
        let client = rawObj.perform(initSel, with: "chargeplan").takeUnretainedValue()
        
        let suppSel = NSSelectorFromString("isMCLSupported")
        let setSel = NSSelectorFromString("setMCLLimit:error:")
        let disSel = NSSelectorFromString("disableMCL:")
        let availSel = NSSelectorFromString("availableChargeLimitsWithError:")
        guard client.responds(to: suppSel),
              client.responds(to: setSel),
              client.responds(to: disSel),
              client.responds(to: availSel),
              let suppMethod = class_getInstanceMethod(cls, suppSel) else {
            return
        }
        
        typealias BoolFn = @convention(c) (AnyObject, Selector) -> Bool
        let isSupported = unsafeBitCast(method_getImplementation(suppMethod), to: BoolFn.self)(client, suppSel)
        guard isSupported else { return }
        
        self.powerUIClass = cls
        self.powerUIClient = client
        self.powerUIAvailableLimits = [80, 85, 90, 95, 100]
        
        if geteuid() == 0, let availMethod = class_getInstanceMethod(cls, availSel) {
            typealias AvailFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> AnyObject?
            var err: NSError? = nil
            if let arr = unsafeBitCast(method_getImplementation(availMethod), to: AvailFn.self)(client, availSel, &err) as? [NSNumber], !arr.isEmpty {
                self.powerUIAvailableLimits = arr.map { $0.intValue }.sorted()
            }
        }
    }
    
    private func hasDirectSMCChargingKeys(_ smc: SMCDriver) -> Bool {
        if smc.getKeyInfo("bfF0") != nil && smc.getKeyInfo("bfD0") != nil && smc.getKeyInfo("bfE0") != nil {
            return true
        }
        if smc.getKeyInfo("CHTE") != nil {
            return true
        }
        if smc.getKeyInfo("CH0B") != nil {
            return true
        }
        if smc.getKeyInfo("BCLM") != nil {
            return true
        }
        return false
    }
    
    private func detectBestMode() -> ChargingMode {
        // 1. Direct AppleSMC charge-inhibit keys (True AC Pass-Through for 20-100%)
        if let smc = smcDriver, hasDirectSMCChargingKeys(smc) {
            return .directSMC
        }
        
        // 2. macOS Native PowerUISmartChargeClient (True AC Pass-Through on gated macOS 27+ firmware)
        if powerUIClient != nil {
            return .nativePowerUI
        }
        
        // 3. Fallback to auxiliary CLI if installed
        let possibleCLIs = [
            "/usr/local/bin/smc",
            "/opt/homebrew/bin/smc",
            "/opt/homebrew/bin/batt",
            "/usr/local/bin/batt"
        ]
        for path in possibleCLIs {
            if FileManager.default.isExecutableFile(atPath: path) {
                return .auxiliaryCLI(path: path)
            }
        }
        
        return .simulation
    }
    
    public var modeName: String {
        switch activeMode {
        case .directSMC:
            return "Direct AppleSMC Driver (AC Pass-Through)"
        case .nativePowerUI:
            return "macOS Native PowerUI (AC Pass-Through)"
        case .auxiliaryCLI(let path):
            return "Auxiliary Engine (\(path))"
        case .simulation:
            return "Simulation (Driver Emulation)"
        }
    }
    
    public func setChargingInhibited(_ inhibit: Bool) -> Bool {
        switch activeMode {
        case .directSMC:
            guard let smc = smcDriver else { return false }
            
            // 1. Firmware-managed hysteresis keys (bfF0 / bfD0 / bfE0)
            if smc.getKeyInfo("bfF0") != nil && smc.getKeyInfo("bfD0") != nil && smc.getKeyInfo("bfE0") != nil {
                if inhibit {
                    let upper = UInt32(max(30, min(100, currentLimit)))
                    let lower = UInt32(max(25, Int(upper) - max(1, currentDelta)))
                    _ = smc.writeByte("bfF0", value: 0x00)
                    let sUpper = smc.writeUInt32LE("bfD0", value: upper)
                    let sLower = smc.writeUInt32LE("bfE0", value: lower)
                    let sAct = smc.writeByte("bfF0", value: 0x02)
                    return sUpper && sLower && sAct
                } else {
                    return smc.writeByte("bfF0", value: 0x00)
                }
            }
            
            // 2. Modern Apple Silicon 4-byte charge inhibit key (CHTE)
            if smc.getKeyInfo("CHTE") != nil {
                let bytes: [UInt8] = inhibit ? [0x01, 0x00, 0x00, 0x00] : [0x00, 0x00, 0x00, 0x00]
                return smc.writeBytes("CHTE", bytes: bytes)
            }
            
            // 3. Legacy Apple Silicon 1-byte charge inhibit keys (CH0B & CH0C)
            if smc.getKeyInfo("CH0B") != nil {
                let val: UInt8 = inhibit ? 0x02 : 0x00
                let s1 = smc.writeByte("CH0B", value: val)
                if smc.getKeyInfo("CH0C") != nil {
                    _ = smc.writeByte("CH0C", value: val)
                }
                return s1
            }
            
            return false
            
        case .nativePowerUI:
            if inhibit {
                return applyPowerUILimit(currentLimit)
            } else {
                return disablePowerUILimit()
            }
            
        case .auxiliaryCLI(let path):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            if path.contains("batt") {
                // Never use `batt adapter disable` (which cuts AC wall power and drains the battery).
                // Use `batt limit` / `batt disable` for AC pass-through charge limiting.
                process.arguments = inhibit ? ["limit", "\(max(30, min(100, currentLimit)))"] : ["disable"]
            } else {
                // smc -k CH0B -w <val>
                process.arguments = ["-k", "CH0B", "-w", inhibit ? "02" : "00"]
            }
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
            
        case .simulation:
            return true
        }
    }
    
    public func setChargeLimitPercentage(_ limit: Int, delta: Int = 3, force: Bool = false) -> Bool {
        let clamped = max(30, min(100, limit))
        self.currentLimit = clamped
        self.currentDelta = max(1, delta)
        if force {
            lastPublishedLimit = -1
        }
        
        switch activeMode {
        case .directSMC:
            guard let smc = smcDriver else { return false }
            if smc.getKeyInfo("bfF0") != nil && smc.getKeyInfo("bfD0") != nil && smc.getKeyInfo("bfE0") != nil {
                if clamped >= 100 {
                    return smc.writeByte("bfF0", value: 0x00)
                }
                let upper = UInt32(clamped)
                let lower = UInt32(max(25, clamped - self.currentDelta))
                _ = smc.writeByte("bfF0", value: 0x00)
                let sUpper = smc.writeUInt32LE("bfD0", value: upper)
                let sLower = smc.writeUInt32LE("bfE0", value: lower)
                let sAct = smc.writeByte("bfF0", value: 0x02)
                return sUpper && sLower && sAct
            }
            if smc.getKeyInfo("BCLM") != nil {
                return smc.writeByte("BCLM", value: UInt8(clamped))
            }
            // CHTE / CH0B are toggled dynamically by AIGovernor
            return true
            
        case .nativePowerUI:
            if clamped >= 100 {
                return disablePowerUILimit()
            }
            return applyPowerUILimit(clamped)
            
        case .auxiliaryCLI(let path):
            if path.contains("batt") {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = clamped >= 100 ? ["disable"] : ["limit", "\(clamped)"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus == 0
                } catch {
                    return false
                }
            }
            return true
            
        case .simulation:
            return true
        }
    }
    
    private func getCurrentPowerUILimit() -> (enabled: Bool, limit: Int)? {
        guard let cls = powerUIClass, let client = powerUIClient else { return nil }
        let getSel = NSSelectorFromString("getMCLLimitWithError:")
        let enSel = NSSelectorFromString("isMCLCurrentlyEnabled:")
        guard client.responds(to: getSel),
              client.responds(to: enSel),
              let getMethod = class_getInstanceMethod(cls, getSel),
              let enMethod = class_getInstanceMethod(cls, enSel) else {
            return nil
        }
        typealias GetLimitFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> UInt8
        typealias IsEnabledFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> UInt64
        var err1: NSError? = nil
        var err2: NSError? = nil
        let limit = unsafeBitCast(method_getImplementation(getMethod), to: GetLimitFn.self)(client, getSel, &err1)
        let enabled = unsafeBitCast(method_getImplementation(enMethod), to: IsEnabledFn.self)(client, enSel, &err2)
        if err1 != nil || err2 != nil {
            return nil
        }
        return (enabled != 0, Int(limit))
    }
    
    private func setDirectXPCMCLLimit(_ target: UInt8) -> Bool {
        guard let cls = powerUIClass, let client = powerUIClient else { return false }
        let setSel = NSSelectorFromString("setMCLLimit:error:")
        guard let method = class_getInstanceMethod(cls, setSel) else { return false }
        typealias SetFn = @convention(c) (AnyObject, Selector, UInt8, UnsafeMutablePointer<NSError?>) -> Bool
        var err: NSError? = nil
        return unsafeBitCast(method_getImplementation(method), to: SetFn.self)(client, setSel, target, &err)
    }
    
    /// Highest `chargeSocLimitSoc` currently registered with powerd, if any.
    /// While on battery, powerd often reports no policy even when a ceiling is saved.
    /// The reading is cached for two seconds so status and the governor share one `pmset`.
    public func powerdSocLimit() -> Int? {
        cachedCeiling().value
    }
    
    /// True only when `pmset` itself reported that no ceiling is registered.
    /// A failed or empty capture is not that report.
    public func powerdReportedNoCeiling() -> Bool {
        cachedCeiling().explicitNone
    }
    
    private func cachedCeiling() -> (value: Int?, explicitNone: Bool) {
        powerdLock.lock()
        defer { powerdLock.unlock() }
        if let cache = powerdCache, Date().timeIntervalSince(cache.at) < 2 {
            return (cache.value, cache.explicitNone)
        }
        let text = Self.readPmsetBattlimit()
        let value = Self.parsePowerdSocLimits(text).max()
        let explicitNone = value == nil && text.contains("No battery level limits set")
        powerdCache = (Date(), value, explicitNone)
        return (value, explicitNone)
    }
    
    private func invalidatePowerdCache() {
        powerdLock.lock()
        powerdCache = nil
        powerdLock.unlock()
    }
    
    static func parsePowerdSocLimits(_ text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"chargeSocLimitSoc\s*=\s*(\d{1,3})"#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var values: [Int] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text),
                  let value = Int(text[valueRange]),
                  (1...100).contains(value) else { return }
            values.append(value)
        }
        return values
    }
    
    /// powerd's registered ceilings. Stdout and stderr are read separately:
    /// a shared pipe under launchd came back empty, and an empty capture is
    /// not the same thing as "No battery level limits set". If the direct
    /// read has no ceiling, ask again as the console user.
    private static func readPmsetBattlimit() -> String {
        let direct = runCommand("/usr/bin/pmset", ["-g", "battlimit"])
        if !parsePowerdSocLimits(direct.output).isEmpty {
            return direct.output
        }
        if let uid = consoleUserID() {
            let bounced = runCommand("/bin/launchctl", ["asuser", String(uid), "/usr/bin/pmset", "-g", "battlimit"])
            if !parsePowerdSocLimits(bounced.output).isEmpty {
                return bounced.output
            }
            logBattlimitRead(direct: direct, bounced: bounced, uid: uid)
            return direct.output.isEmpty ? bounced.output : direct.output
        }
        logBattlimitRead(direct: direct, bounced: nil, uid: nil)
        return direct.output
    }
    
    private static let battlimitLogLock = NSLock()
    private static var didLogBattlimitRead = false
    
    /// One line in the daemon log when neither read shows a ceiling, so a
    /// LaunchDaemon that cannot see powerd does not fail silently.
    private static func logBattlimitRead(
        direct: (status: Int32, output: String),
        bounced: (status: Int32, output: String)?,
        uid: uid_t?
    ) {
        battlimitLogLock.lock()
        defer { battlimitLogLock.unlock() }
        guard !didLogBattlimitRead else { return }
        didLogBattlimitRead = true
        func flat(_ text: String) -> String {
            String(text.prefix(180)).replacingOccurrences(of: "\n", with: " ")
        }
        let bouncedText = bounced.map { " asuser=\($0.status):\(flat($0.output))" } ?? ""
        let uidText = uid.map(String.init) ?? "none"
        fputs("pmset battlimit unreadable direct=\(direct.status):\(flat(direct.output))\(bouncedText) console=\(uidText)\n", stdout)
        fflush(stdout)
    }
    
    private static func consoleUserID() -> uid_t? {
        var info = stat()
        guard stat("/dev/console", &info) == 0 else { return nil }
        let uid = info.st_uid
        guard uid != 0 else { return nil }
        return uid
    }
    
    private final class CommandOutput: @unchecked Sendable {
        var out = Data()
        var err = Data()
    }
    
    @discardableResult
    private static func runCommand(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        if environment["PATH"]?.isEmpty != false {
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        }
        process.environment = environment
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let box = CommandOutput()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            box.out = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            box.err = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        let data = box.out + box.err
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, text)
    }
    
    private func applyPowerUILimit(_ requested: Int) -> Bool {
        let clamped = max(20, min(100, requested))
        if clamped == lastPublishedLimit, Date().timeIntervalSince(lastPublishAt) < 15 {
            return true
        }
        invalidatePowerdCache()
        
        // 80–100 is accepted by setMCLLimit:. Below 80 the XPC handler returns
        // PowerUISmartChargingErrorDomain error 4 and leaves the previous ceiling
        // (usually 80) in place, so the battery keeps charging toward that floor.
        if clamped >= 80 {
            if !powerUIAvailableLimits.isEmpty && !powerUIAvailableLimits.contains(clamped) {
                logger.info("Charge limit \(clamped, privacy: .public) is between the advertised steps; sending it directly")
            }
            let ok = setDirectXPCMCLLimit(UInt8(clamped))
            if ok, geteuid() == 0 {
                _ = publishTopOffPreference(limit: clamped, enabled: true)
                notifyChargeLimitChanged(restartAgent: false)
            }
            if ok {
                lastPublishedLimit = clamped
                lastPublishAt = Date()
            } else {
                logger.error("setMCLLimit \(clamped, privacy: .public) was rejected")
            }
            return ok
        }
        
        guard geteuid() == 0 else {
            logger.error("A charge limit below 80% has to be published by the root daemon")
            return false
        }
        
        // Arm the feature, then overwrite the saved value. setMCLLimit: would
        // clamp this back to 80, so it must not be called with the real target.
        if getCurrentPowerUILimit()?.enabled != true {
            _ = enableMCL()
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard publishTopOffPreference(limit: clamped, enabled: true) else {
            logger.error("Failed to write mclLimitValue \(clamped, privacy: .public)")
            return false
        }
        notifyChargeLimitChanged(restartAgent: true)
        lastPublishedLimit = clamped
        lastPublishAt = Date()
        logger.info("Published sub-80 charge ceiling \(clamped, privacy: .public) to powerd")
        return true
    }
    
    private func enableMCL() -> Bool {
        guard let cls = powerUIClass, let client = powerUIClient else { return false }
        let sel = NSSelectorFromString("enableMCL:")
        guard let method = class_getInstanceMethod(cls, sel) else { return false }
        typealias EnFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> Bool
        var err: NSError? = nil
        return unsafeBitCast(method_getImplementation(method), to: EnFn.self)(client, sel, &err)
    }
    
    /// PowerUIAgent (root) reloads this domain on `com.apple.smartcharging.defaultschanged`
    /// and forwards `mclLimitValue` to powerd without the 80–100 XPC check.
    private func publishTopOffPreference(limit: Int, enabled: Bool) -> Bool {
        let domain = "com.apple.smartcharging.topoffprotection" as CFString
        let user = kCFPreferencesCurrentUser
        let host = kCFPreferencesAnyHost
        func put(_ key: String, _ value: CFPropertyList) {
            CFPreferencesSetValue(key as CFString, value, domain, user, host)
        }
        if enabled {
            let number = NSNumber(value: limit)
            put("mclLimitValue", number)
            put("mclTargetSoC", number)
            put("MCLSavedTargetSoC", number)
            put("MCLFeatureState", NSNumber(value: 1))
            put("enabled", kCFBooleanTrue)
        } else {
            put("MCLFeatureState", NSNumber(value: 0))
            put("enabled", kCFBooleanFalse)
            put("mclLimitValue", NSNumber(value: 100))
        }
        return CFPreferencesSynchronize(domain, user, host)
    }
    
    private func notifyChargeLimitChanged(restartAgent: Bool) {
        _ = Self.runCommand("/usr/bin/notifyutil", ["-p", "com.apple.smartcharging.defaultschanged"])
        
        guard restartAgent, geteuid() == 0 else { return }
        // PowerUIAgent reloads the preference on SIGHUP. launchd keeps it running.
        _ = Self.runCommand("/usr/bin/killall", ["-HUP", "PowerUIAgent"])
        Thread.sleep(forTimeInterval: 0.4)
        setupPowerUI()
        invalidatePowerdCache()
    }
    
    private func disablePowerUILimit() -> Bool {
        if let current = getCurrentPowerUILimit(), !current.enabled {
            return true
        }
        guard let cls = powerUIClass, let client = powerUIClient else { return false }
        let disSel = NSSelectorFromString("disableMCL:")
        guard let method = class_getInstanceMethod(cls, disSel) else { return false }
        typealias DisFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> Bool
        var err: NSError? = nil
        let res = unsafeBitCast(method_getImplementation(method), to: DisFn.self)(client, disSel, &err)
        if res, geteuid() == 0 {
            _ = publishTopOffPreference(limit: 100, enabled: false)
            notifyChargeLimitChanged(restartAgent: false)
            lastPublishedLimit = 100
            lastPublishAt = Date()
        }
        return res
    }
}
