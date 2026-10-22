import Foundation

public class AIGovernor {
    public let monitor: BatteryMonitor
    public let hardware: HardwareBackend
    public private(set) var config: GovernorConfig
    public private(set) var state: GovernorState
    
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.wixe.chargecap.governor", qos: .utility)
    private let stateLock = NSLock()
    
    public init(config: GovernorConfig = ConfigManager.shared.load()) {
        self.monitor = BatteryMonitor()
        self.hardware = HardwareBackend()
        self.config = config
        self.state = GovernorState.initial
        self.state.activeTarget = config.targetLimit
        _ = self.hardware.setChargeLimitPercentage(config.targetLimit, delta: config.sailingEnabled ? config.sailingDelta : 1)
    }
    
    public func updateConfig(_ newConfig: GovernorConfig) {
        stateLock.lock()
        self.config = newConfig
        self.state.activeTarget = newConfig.targetLimit
        stateLock.unlock()
        _ = ConfigManager.shared.save(newConfig)
        _ = hardware.setChargeLimitPercentage(newConfig.targetLimit, delta: newConfig.sailingEnabled ? newConfig.sailingDelta : 1)
        evaluateTick()
    }
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // Initial setup
        _ = hardware.setChargeLimitPercentage(config.targetLimit, delta: config.sailingEnabled ? config.sailingDelta : 1)
        evaluateTick()
        
        queue.async { [weak self] in
            while self?.isRunning == true {
                let interval = self?.config.pollIntervalSeconds ?? 5.0
                Thread.sleep(forTimeInterval: interval)
                self?.evaluateTick()
            }
        }
    }
    
    public func stop() {
        isRunning = false
        // Restore normal charging on shutdown
        _ = hardware.setChargingInhibited(false)
    }
    
    public func evaluateTick() {
        let status = monitor.getCurrentStatus()
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard status.isACConnected else {
            state.modeDescription = "Running on Battery Power (\(status.percent)%)"
            return
        }
        
        // 1. Thermal Protection Rule
        if config.thermalProtectionEnabled && (status.thermalState.contains("Serious") || status.thermalState.contains("Critical")) {
            if !state.isThermalThrottled {
                _ = hardware.setChargingInhibited(true)
                state.isThermalThrottled = true
                state.isChargingInhibited = true
                state.lastActionTimestamp = Date()
                state.lastActionReason = "Thermal protection activated (Thermal State: \(status.thermalState))"
            }
            state.modeDescription = "Thermal Throttling Active (Cooling Down)"
            return
        } else if state.isThermalThrottled {
            state.isThermalThrottled = false
            state.lastActionReason = "Thermal state normalized"
        }
        
        let target = config.targetLimit
        let lowerBound = max(20, target - (config.sailingEnabled ? config.sailingDelta : 1))
        
        // 2. Closed-Loop Upper Limit Enforcement
        if status.percent >= target {
            if status.isCharging || !state.isChargingInhibited {
                let success = hardware.setChargingInhibited(true)
                state.isChargingInhibited = true
                state.isSailing = true
                state.lastActionTimestamp = Date()
                state.lastActionReason = "Target reached (\(status.percent)% >= \(target)%). Inhibiting charge."
                state.modeDescription = "Holding Cap at \(target)% (Sailing Idle)"
                if !success { state.consecutiveErrors += 1 }
            } else {
                state.modeDescription = "Holding Cap at \(target)% (Idle AC Pass-through)"
            }
            return
        }
        
        // 3. Lower Bound Hysteresis (Micro-Sailing)
        if status.percent <= lowerBound {
            if state.isChargingInhibited || !status.isCharging {
                let success = hardware.setChargingInhibited(false)
                state.isChargingInhibited = false
                state.isSailing = false
                state.lastActionTimestamp = Date()
                state.lastActionReason = "Battery reached lower sailing bound (\(status.percent)% <= \(lowerBound)%). Re-enabling charge."
                state.modeDescription = "Gentle Charging to \(target)%"
                if !success { state.consecutiveErrors += 1 }
            } else {
                state.modeDescription = "Charging to \(target)% (\(status.percent)%)"
            }
            return
        }
        
        // 4. In Between Lower and Upper Bound (Sailing Mode)
        if config.sailingEnabled && state.isSailing {
            state.modeDescription = "Micro-Sailing (\(status.percent)% within \(lowerBound)%-\(target)%)"
        } else {
            state.modeDescription = "Optimal Range (\(status.percent)%)"
        }
    }
    
    public func getCombinedReport() -> [String: Any] {
        stateLock.lock()
        defer { stateLock.unlock() }
        let batt = monitor.getCurrentStatus()
        
        return [
            "battery": [
                "percent": batt.percent,
                "is_charging": batt.isCharging,
                "is_ac_connected": batt.isACConnected,
                "is_fully_charged": batt.isFullyCharged,
                "cycle_count": batt.cycleCount,
                "voltage_mv": batt.voltageMV,
                "amperage_ma": batt.amperageMA,
                "wattage_w": batt.wattageW,
                "health_percent": batt.healthPercent,
                "design_capacity_mah": batt.designCapacityMAh,
                "full_capacity_mah": batt.fullChargeCapacityMAh,
                "thermal_state": batt.thermalState,
                "serial_number": batt.serialNumber
            ],
            "governor": [
                "target_limit": config.targetLimit,
                "sailing_enabled": config.sailingEnabled,
                "sailing_delta": config.sailingDelta,
                "charging_inhibited": state.isChargingInhibited,
                "thermal_throttled": state.isThermalThrottled,
                "mode": state.modeDescription,
                "backend": hardware.modeName,
                "last_action": state.lastActionReason,
                "last_action_time": ISO8601DateFormatter().string(from: state.lastActionTimestamp)
            ]
        ]
    }
}
