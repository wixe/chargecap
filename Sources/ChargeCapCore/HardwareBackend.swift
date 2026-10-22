import Foundation
import OSLog

public enum ChargingMode {
    case directSMC
    case auxiliaryCLI(path: String)
    case simulation
}

public class HardwareBackend {
    private var smcDriver: SMCDriver?
    private var activeMode: ChargingMode = .simulation
    private let logger = Logger(subsystem: "com.wixe.chargecap", category: "HardwareBackend")
    
    public init() {
        self.smcDriver = SMCDriver()
        self.activeMode = detectBestMode()
    }
    
    private func detectBestMode() -> ChargingMode {
        // 1. Test direct SMC
        if let smc = smcDriver {
            if smc.getKeyInfo("CH0B") != nil || smc.getKeyInfo("BCLM") != nil {
                return .directSMC
            }
        }
        
        // 2. Check for batt CLI
        let possibleCLIs = [
            "/opt/homebrew/bin/batt",
            "/usr/local/bin/batt",
            "/usr/local/bin/smc",
            "/opt/homebrew/bin/smc"
        ]
        for path in possibleCLIs {
            if FileManager.default.isExecutableFile(atPath: path) {
                return .auxiliaryCLI(path: path)
            }
        }
        
        // Fallback to direct SMC if driver opened, else simulation
        return smcDriver != nil ? .directSMC : .simulation
    }
    
    public var modeName: String {
        switch activeMode {
        case .directSMC: return "Direct AppleSMC Driver"
        case .auxiliaryCLI(let path): return "Auxiliary Engine (\(path))"
        case .simulation: return "Simulation (Driver Emulation)"
        }
    }
    
    public func setChargingInhibited(_ inhibit: Bool) -> Bool {
        switch activeMode {
        case .directSMC:
            guard let smc = smcDriver else { return false }
            // CH0B: 0x02 = inhibit, 0x00 = enable
            let val: UInt8 = inhibit ? 0x02 : 0x00
            let s1 = smc.writeByte("CH0B", value: val)
            if !s1 {
                // Try BCLM as fallback
                let bclmVal: UInt8 = inhibit ? 50 : 100
                return smc.writeByte("BCLM", value: bclmVal)
            }
            return s1
            
        case .auxiliaryCLI(let path):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            if path.contains("batt") {
                // batt adapter disable/enable or limit
                process.arguments = inhibit ? ["adapter", "disable"] : ["adapter", "enable"]
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
    
    public func setChargeLimitPercentage(_ limit: Int) -> Bool {
        let clamped = max(20, min(100, limit))
        
        switch activeMode {
        case .directSMC:
            if let smc = smcDriver {
                let success = smc.writeByte("BCLM", value: UInt8(clamped))
                if success { return true }
            }
            // If BCLM direct fails, use CH0B logic in governor
            return true
            
        case .auxiliaryCLI(let path):
            if path.contains("batt") {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["limit", "\(clamped)"]
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
}
