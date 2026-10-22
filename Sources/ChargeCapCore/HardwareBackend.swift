import Foundation
import ObjectiveC
import OSLog

public enum ChargingMode {
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
    private let logger = Logger(subsystem: "com.wixe.chargecap", category: "HardwareBackend")
    
    // Cached PowerUISmartChargeClient instance
    private var powerUIClient: AnyObject?
    private var powerUIClass: NSObject.Type?
    private var powerUIAvailableLimits: [Int] = []
    
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
        let client = rawObj.perform(initSel, with: "chargecap").takeUnretainedValue()
        
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
        
        if let availMethod = class_getInstanceMethod(cls, availSel) {
            typealias AvailFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> AnyObject?
            var err: NSError? = nil
            if let arr = unsafeBitCast(method_getImplementation(availMethod), to: AvailFn.self)(client, availSel, &err) as? [NSNumber] {
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
                    let upper = UInt32(max(20, min(100, currentLimit)))
                    let lower = UInt32(max(19, Int(upper) - max(1, currentDelta)))
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
            
            // 4. Intel SMC charge limit key (BCLM)
            if smc.getKeyInfo("BCLM") != nil {
                let bclmVal: UInt8 = inhibit ? UInt8(max(20, min(100, currentLimit))) : 100
                return smc.writeByte("BCLM", value: bclmVal)
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
                process.arguments = inhibit ? ["limit", "\(max(20, min(100, currentLimit)))"] : ["disable"]
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
    
    public func setChargeLimitPercentage(_ limit: Int, delta: Int = 3) -> Bool {
        let clamped = max(20, min(100, limit))
        self.currentLimit = clamped
        self.currentDelta = max(1, delta)
        
        switch activeMode {
        case .directSMC:
            guard let smc = smcDriver else { return false }
            if smc.getKeyInfo("bfF0") != nil && smc.getKeyInfo("bfD0") != nil && smc.getKeyInfo("bfE0") != nil {
                if clamped >= 100 {
                    return smc.writeByte("bfF0", value: 0x00)
                }
                let upper = UInt32(clamped)
                let lower = UInt32(max(19, clamped - self.currentDelta))
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
    
    private func nearestPowerUILimit(_ requested: Int) -> Int {
        guard !powerUIAvailableLimits.isEmpty else {
            return max(80, min(100, requested))
        }
        for candidate in powerUIAvailableLimits where candidate >= requested {
            return candidate
        }
        return powerUIAvailableLimits.last ?? 80
    }
    
    private func applyPowerUILimit(_ requested: Int) -> Bool {
        guard let cls = powerUIClass, let client = powerUIClient else { return false }
        let target = UInt8(nearestPowerUILimit(requested))
        let setSel = NSSelectorFromString("setMCLLimit:error:")
        guard let method = class_getInstanceMethod(cls, setSel) else { return false }
        typealias SetFn = @convention(c) (AnyObject, Selector, UInt8, UnsafeMutablePointer<NSError?>) -> Bool
        var err: NSError? = nil
        return unsafeBitCast(method_getImplementation(method), to: SetFn.self)(client, setSel, target, &err)
    }
    
    private func disablePowerUILimit() -> Bool {
        guard let cls = powerUIClass, let client = powerUIClient else { return false }
        let disSel = NSSelectorFromString("disableMCL:")
        guard let method = class_getInstanceMethod(cls, disSel) else { return false }
        typealias DisFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> Bool
        var err: NSError? = nil
        return unsafeBitCast(method_getImplementation(method), to: DisFn.self)(client, disSel, &err)
    }
}
