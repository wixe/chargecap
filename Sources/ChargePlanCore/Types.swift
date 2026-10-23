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
    public let notChargingReason: Int
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
        notChargingReason: Int = 0,
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
        self.notChargingReason = notChargingReason
        self.timestamp = timestamp
    }
}

public struct GovernorConfig: Codable, Equatable {
    public var targetLimit: Int
    public var deadbandEnabled: Bool
    public var deadbandDelta: Int
    public var thermalProtectionEnabled: Bool
    public var autoServerMode: Bool
    public var pollIntervalSeconds: Double
    
    enum CodingKeys: String, CodingKey {
        case targetLimit
        case deadbandEnabled
        case deadbandDelta
        case sailingEnabled
        case sailingDelta
        case thermalProtectionEnabled
        case autoServerMode
        case pollIntervalSeconds
    }
    
    public init(
        targetLimit: Int,
        deadbandEnabled: Bool,
        deadbandDelta: Int,
        thermalProtectionEnabled: Bool,
        autoServerMode: Bool,
        pollIntervalSeconds: Double
    ) {
        self.targetLimit = targetLimit
        self.deadbandEnabled = deadbandEnabled
        self.deadbandDelta = deadbandDelta
        self.thermalProtectionEnabled = thermalProtectionEnabled
        self.autoServerMode = autoServerMode
        self.pollIntervalSeconds = pollIntervalSeconds
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.targetLimit = try c.decodeIfPresent(Int.self, forKey: .targetLimit) ?? 50
        self.deadbandEnabled = try c.decodeIfPresent(Bool.self, forKey: .deadbandEnabled)
            ?? c.decodeIfPresent(Bool.self, forKey: .sailingEnabled)
            ?? true
        self.deadbandDelta = try c.decodeIfPresent(Int.self, forKey: .deadbandDelta)
            ?? c.decodeIfPresent(Int.self, forKey: .sailingDelta)
            ?? 3
        self.thermalProtectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .thermalProtectionEnabled) ?? true
        self.autoServerMode = try c.decodeIfPresent(Bool.self, forKey: .autoServerMode) ?? true
        self.pollIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds) ?? 5.0
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(targetLimit, forKey: .targetLimit)
        try c.encode(deadbandEnabled, forKey: .deadbandEnabled)
        try c.encode(deadbandDelta, forKey: .deadbandDelta)
        try c.encode(thermalProtectionEnabled, forKey: .thermalProtectionEnabled)
        try c.encode(autoServerMode, forKey: .autoServerMode)
        try c.encode(pollIntervalSeconds, forKey: .pollIntervalSeconds)
    }
    
    public static var `default`: GovernorConfig {
        GovernorConfig(
            targetLimit: 50,
            deadbandEnabled: true,
            deadbandDelta: 3,
            thermalProtectionEnabled: true,
            autoServerMode: true,
            pollIntervalSeconds: 5.0
        )
    }
}

public struct GovernorState: Codable {
    public var activeTarget: Int
    public var isChargingInhibited: Bool
    public var inDeadband: Bool
    public var isThermalThrottled: Bool
    public var modeDescription: String
    public var lastActionTimestamp: Date
    public var lastActionReason: String
    public var consecutiveErrors: Int
    
    public static var initial: GovernorState {
        GovernorState(
            activeTarget: 50,
            isChargingInhibited: false,
            inDeadband: false,
            isThermalThrottled: false,
            modeDescription: "Initializing",
            lastActionTimestamp: Date(),
            lastActionReason: "Daemon started",
            consecutiveErrors: 0
        )
    }
}
