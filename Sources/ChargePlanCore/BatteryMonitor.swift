import Foundation
import IOKit
import IOKit.ps

public class BatteryMonitor {
    public init() {}
    
    public func getCurrentStatus() -> BatteryStatus {
        var percent = 0
        var isCharging = false
        var isACConnected = false
        var isFullyCharged = false
        var timeRemaining = -1
        var serialNumber = "Unknown"
        
        // 1. Read IOPS (I/O Power Source)
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as [CFTypeRef]? {
            for s in sources {
                if let desc = IOPSGetPowerSourceDescription(blob, s)?.takeUnretainedValue() as? [String: Any] {
                    if let cur = desc[kIOPSCurrentCapacityKey] as? Int {
                        percent = cur
                    }
                    if let charging = desc[kIOPSIsChargingKey] as? Bool {
                        isCharging = charging
                    } else if let chargingInt = desc[kIOPSIsChargingKey] as? Int {
                        isCharging = (chargingInt != 0)
                    }
                    if let charged = desc[kIOPSIsChargedKey] as? Bool {
                        isFullyCharged = charged
                    }
                    if let state = desc[kIOPSPowerSourceStateKey] as? String {
                        isACConnected = (state == kIOPSACPowerValue)
                    }
                    if let time = desc[kIOPSTimeToEmptyKey] as? Int {
                        timeRemaining = time
                    }
                    if let serial = desc[kIOPSHardwareSerialNumberKey] as? String {
                        serialNumber = serial
                    }
                }
            }
        }
        
        // 2. Read AppleSmartBattery from IOKit Registry
        var cycleCount = 0
        var voltageMV = 0
        var amperageMA = 0
        var designCapacity = 0
        var fullCapacity = 0
        var remainingCapacity = 0
        var nominalCapacity = 0
        var wattage = 0.0
        var notChargingReason = 0
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                
                cycleCount = dict["CycleCount"] as? Int ?? 0
                voltageMV = dict["Voltage"] as? Int ?? 0
                
                if let amp = dict["Amperage"] as? Int {
                    amperageMA = amp
                } else if let instAmp = dict["InstantAmperage"] as? Int {
                    amperageMA = instAmp
                }
                
                if let extConn = dict["ExternalConnected"] as? Bool {
                    isACConnected = extConn
                } else if let extInt = dict["ExternalConnected"] as? Int {
                    isACConnected = (extInt != 0)
                }
                
                if let fullyCharged = dict["FullyCharged"] as? Bool {
                    isFullyCharged = fullyCharged
                }
                
                if let bdata = dict["BatteryData"] as? [String: Any] {
                    designCapacity = bdata["DesignCapacity"] as? Int ?? 0
                    fullCapacity = bdata["FullChargeCapacity"] as? Int ?? 0
                    nominalCapacity = bdata["NominalChargeCapacity"] as? Int ?? 0
                    remainingCapacity = bdata["RemainingCapacity"] as? Int ?? 0
                    if percent == 0, let cap = bdata["CurrentCapacity"] as? Int {
                        percent = cap
                    }
                }
                
                if remainingCapacity == 0, let cur = dict["CurrentCapacity"] as? Int, cur > 100 {
                    remainingCapacity = cur
                }
                
                if let cdata = dict["ChargerData"] as? [String: Any] {
                    if let chg = cdata["IsCharging"] as? Int {
                        isCharging = (chg != 0)
                    }
                }
                
                if let reason = dict["NotChargingReason"] as? Int {
                    notChargingReason = reason
                }
                
                if let s = dict["Serial"] as? String, serialNumber == "Unknown" {
                    serialNumber = s
                }
            }
            IOObjectRelease(service)
        }
        
        if voltageMV > 0 && amperageMA != 0 {
            // V * A / 1,000,000 = Watts
            wattage = Double(voltageMV) * Double(amperageMA) / 1_000_000.0
        }
        
        var health = 100.0
        if designCapacity > 0 && fullCapacity > 0 {
            health = (Double(fullCapacity) / Double(designCapacity)) * 100.0
            if health > 100.0 { health = 100.0 }
        }
        
        var exactPercent = Double(percent)
        if fullCapacity > 0 && remainingCapacity > 0 {
            let raw = (Double(remainingCapacity) / Double(fullCapacity)) * 100.0
            exactPercent = max(0.0, min(100.0, (raw * 100.0).rounded() / 100.0))
        }
        
        let tState = ProcessInfo.processInfo.thermalState
        let thermalString: String
        switch tState {
        case .nominal: thermalString = "Nominal"
        case .fair: thermalString = "Fair"
        case .serious: thermalString = "Serious (Throttled)"
        case .critical: thermalString = "Critical"
        @unknown default: thermalString = "Unknown"
        }
        
        return BatteryStatus(
            percent: percent,
            exactPercent: exactPercent,
            isCharging: isCharging,
            isACConnected: isACConnected,
            isFullyCharged: isFullyCharged,
            cycleCount: cycleCount,
            voltageMV: voltageMV,
            amperageMA: amperageMA,
            wattageW: wattage,
            designCapacityMAh: designCapacity,
            fullChargeCapacityMAh: fullCapacity,
            remainingCapacityMAh: remainingCapacity,
            nominalCapacityMAh: nominalCapacity,
            healthPercent: (health * 10).rounded() / 10.0,
            timeRemainingMinutes: timeRemaining,
            serialNumber: serialNumber,
            thermalState: thermalString,
            notChargingReason: notChargingReason
        )
    }
}
