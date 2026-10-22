import Foundation

public struct BatteryStatus: Codable {
    public let percent: Int
    public let isCharging: Bool
    public let isACConnected: Bool
    public let isFullyCharged: Bool
    public let cycleCount: Int
    public let voltageMV: Int
    public let amperageMA: Int
    public let wattageW: Double
    public let designCapacityMAh: Int
    public let fullChargeCapacityMAh: Int
    public let nominalCapacityMAh: Int
    public let healthPercent: Double
    public let timeRemainingMinutes: Int
    public let serialNumber: String
    public let thermalState: String
    public let timestamp: Date
    
    public init(
        percent: Int,
        isCharging: Bool,
        isACConnected: Bool,
        isFullyCharged: Bool,
        cycleCount: Int,
        voltageMV: Int,
        amperageMA: Int,
        wattageW: Double,
        designCapacityMAh: Int,
        fullChargeCapacityMAh: Int,
        nominalCapacityMAh: Int,
        healthPercent: Double,
        timeRemainingMinutes: Int,
        serialNumber: String,
        thermalState: String,
        timestamp: Date = Date()
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isACConnected = isACConnected
        self.isFullyCharged = isFullyCharged
        self.cycleCount = cycleCount
        self.voltageMV = voltageMV
        self.amperageMA = amperageMA
        self.wattageW = wattageW
        self.designCapacityMAh = designCapacityMAh
        self.fullChargeCapacityMAh = fullChargeCapacityMAh
        self.nominalCapacityMAh = nominalCapacityMAh
        self.healthPercent = healthPercent
        self.timeRemainingMinutes = timeRemainingMinutes
        self.serialNumber = serialNumber
        self.thermalState = thermalState
        self.timestamp = timestamp
    }
}

public struct GovernorConfig: Codable, Equatable {
    public var targetLimit: Int
    public var sailingEnabled: Bool
    public var sailingDelta: Int
    public var thermalProtectionEnabled: Bool
    public var autoServerMode: Bool
    public var pollIntervalSeconds: Double
    
    public init(
        targetLimit: Int,
        sailingEnabled: Bool,
        sailingDelta: Int,
        thermalProtectionEnabled: Bool,
        autoServerMode: Bool,
        pollIntervalSeconds: Double
    ) {
        self.targetLimit = targetLimit
        self.sailingEnabled = sailingEnabled
        self.sailingDelta = sailingDelta
        self.thermalProtectionEnabled = thermalProtectionEnabled
        self.autoServerMode = autoServerMode
        self.pollIntervalSeconds = pollIntervalSeconds
    }
    
    public static var `default`: GovernorConfig {
        GovernorConfig(
            targetLimit: 50,
            sailingEnabled: true,
            sailingDelta: 3,
            thermalProtectionEnabled: true,
            autoServerMode: true,
            pollIntervalSeconds: 5.0
        )
    }
}

public struct GovernorState: Codable {
    public var activeTarget: Int
    public var isChargingInhibited: Bool
    public var isSailing: Bool
    public var isThermalThrottled: Bool
    public var modeDescription: String
    public var lastActionTimestamp: Date
    public var lastActionReason: String
    public var consecutiveErrors: Int
    
    public static var initial: GovernorState {
        GovernorState(
            activeTarget: 50,
            isChargingInhibited: false,
            isSailing: false,
            isThermalThrottled: false,
            modeDescription: "Initializing",
            lastActionTimestamp: Date(),
            lastActionReason: "Daemon started",
            consecutiveErrors: 0
        )
    }
}
