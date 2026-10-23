import Foundation

public class AIGovernor {
    public let monitor: BatteryMonitor
    public let hardware: HardwareBackend
    public private(set) var config: GovernorConfig
    public private(set) var state: GovernorState
    
    private var isRunning = false
    private let queue = DispatchQueue(label: "io.github.wixe.chargeplan.governor", qos: .utility)
    private let stateLock = NSLock()
    
    public init(config: GovernorConfig = ConfigManager.shared.load()) {
        self.monitor = BatteryMonitor()
        self.hardware = HardwareBackend()
        self.config = config
        self.state = GovernorState.initial
        self.state.activeTarget = config.targetLimit
        _ = self.hardware.setChargeLimitPercentage(config.targetLimit, delta: config.driftEnabled ? config.driftMargin : 1)
    }
    
    public func updateConfig(_ newConfig: GovernorConfig) {
        stateLock.lock()
        self.config = newConfig
        self.state.activeTarget = newConfig.targetLimit
        stateLock.unlock()
        _ = ConfigManager.shared.save(newConfig)
        _ = hardware.setChargeLimitPercentage(newConfig.targetLimit, delta: newConfig.driftEnabled ? newConfig.driftMargin : 1)
        evaluateTick()
    }
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // Initial setup
        _ = hardware.setChargeLimitPercentage(config.targetLimit, delta: config.driftEnabled ? config.driftMargin : 1)
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
        let diskConfig = ConfigManager.shared.load()
        stateLock.lock()
        defer { stateLock.unlock() }
        
        if diskConfig != self.config {
            self.config = diskConfig
            self.state.activeTarget = diskConfig.targetLimit
            _ = hardware.setChargeLimitPercentage(diskConfig.targetLimit, delta: diskConfig.driftEnabled ? diskConfig.driftMargin : 1)
        }
        
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
        let target = config.targetLimit
        let isNative = hardware.modeName.contains("Native PowerUI")
        let effectiveTarget = isNative ? max(80, target) : target
        let lowerBound = max(20, effectiveTarget - (config.driftEnabled ? config.driftMargin : 1))
        
        // On the macOS native PowerUI path the firmware owns the SoC ceiling.
        // Disabling the limit when the percentage dips a few points re-enables charging
        // and creates unnecessary cycles. Keep the ceiling sticky and only re-assert it.
        if isNative {
            // Always keep the designated limit armed while on AC.
            if !state.isChargingInhibited {
                let success = hardware.setChargeLimitPercentage(target, delta: config.driftEnabled ? config.driftMargin : 1)
                state.isChargingInhibited = true
                state.lastActionTimestamp = Date()
                state.lastActionReason = "Native SoC limit re-asserted at \(effectiveTarget)%"
                if !success { state.consecutiveErrors += 1 }
            }
            
            let floorSuffix = target < 80 ? " (Apple 80% Hardware Floor)" : ""
            if status.percent >= effectiveTarget {
                state.inDrift = true
                state.modeDescription = status.amperageMA == 0
                    ? "Holding Cap at \(effectiveTarget)%\(floorSuffix) (Idle AC Pass-Through)"
                    : "Holding Cap at \(effectiveTarget)%\(floorSuffix) (AC Pass-Through)"
            } else if status.percent <= lowerBound && config.driftEnabled {
                // Firmware will top up on its own; we do not disable the limit.
                state.inDrift = false
                state.modeDescription = "Native limit armed at \(effectiveTarget)%\(floorSuffix) — battery at \(status.percent)% (topping up)"
            } else {
                state.modeDescription = "Native SoC ceiling active at \(effectiveTarget)%\(floorSuffix) (\(status.percent)%)"
            }
            return
        }
        
        // Legacy / direct-SMC path: classic hysteresis
        // 2. Closed-Loop Upper Limit Enforcement
        if status.percent >= target {
            if status.isCharging || !state.isChargingInhibited {
                let success = hardware.setChargingInhibited(true)
                state.isChargingInhibited = true
                state.inDrift = true
                state.lastActionTimestamp = Date()
                state.lastActionReason = "Target reached (\(status.percent)% >= \(target)%). Inhibiting charge."
                state.modeDescription = "Holding Cap at \(target)% (AC Pass-Through)"
                if !success { state.consecutiveErrors += 1 }
            } else {
                state.modeDescription = "Holding Cap at \(target)% (Idle AC Pass-Through)"
            }
            return
        }
        
        // 3. Lower Bound (Drift Recovery)
        if status.percent <= lowerBound {
            if state.isChargingInhibited || !status.isCharging {
                let success = hardware.setChargingInhibited(false)
                state.isChargingInhibited = false
                state.inDrift = false
                state.lastActionTimestamp = Date()
                state.lastActionReason = "Battery reached lower drift threshold (\(status.percent)% <= \(lowerBound)%). Re-enabling charge."
                state.modeDescription = "Gentle Charging to \(target)%"
                if !success { state.consecutiveErrors += 1 }
            } else {
                state.modeDescription = "Charging to \(target)% (\(status.percent)%)"
            }
            return
        }
        
        // 4. Within Drift Margin Window
        if config.driftEnabled && state.inDrift {
            state.modeDescription = "Drift Margin (\(status.percent)% within \(lowerBound)%-\(target)%)"
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
                "exact_percent": batt.exactPercent,
                "remaining_capacity_mah": batt.remainingCapacityMAh,
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
                "not_charging_reason": batt.notChargingReason,
                "serial_number": batt.serialNumber
            ],
            "governor": [
                "version": ChargePlanVersion,
                "target_limit": config.targetLimit,
                "drift_enabled": config.driftEnabled,
                "drift_margin": config.driftMargin,
                "deadband_enabled": config.driftEnabled,
                "deadband_delta": config.driftMargin,
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
