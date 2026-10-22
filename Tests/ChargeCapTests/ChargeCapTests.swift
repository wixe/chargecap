import XCTest
@testable import ChargeCapCore

final class ChargeCapTests: XCTestCase {
    func testBatteryMonitor() {
        let monitor = BatteryMonitor()
        let status = monitor.getCurrentStatus()
        XCTAssertGreaterThanOrEqual(status.percent, 0)
        XCTAssertLessThanOrEqual(status.percent, 100)
        XCTAssertFalse(status.serialNumber.isEmpty)
    }
    
    func testConfigManager() {
        let cfg = GovernorConfig.default
        XCTAssertEqual(cfg.targetLimit, 50)
        XCTAssertTrue(cfg.sailingEnabled)
        XCTAssertEqual(cfg.sailingDelta, 3)
    }
    
    func testGovernorInitialization() {
        let governor = AIGovernor()
        let report = governor.getCombinedReport()
        XCTAssertNotNil(report["battery"])
        XCTAssertNotNil(report["governor"])
    }
    
    func testConfigSerialization() throws {
        let cfg = GovernorConfig(
            targetLimit: 80,
            sailingEnabled: false,
            sailingDelta: 5,
            thermalProtectionEnabled: true,
            autoServerMode: false,
            pollIntervalSeconds: 10.0
        )
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(GovernorConfig.self, from: data)
        XCTAssertEqual(decoded.targetLimit, 80)
        XCTAssertFalse(decoded.sailingEnabled)
        XCTAssertEqual(decoded.sailingDelta, 5)
    }
    
    func testSMCParamStructLayout() {
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.size, 80)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.stride, 80)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.key), 0)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.vers), 4)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.pLimitData), 12)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo), 28)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.result), 40)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.status), 41)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.data8), 42)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.data32), 44)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.bytes), 48)
    }
}
