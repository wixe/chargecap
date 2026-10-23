import XCTest
@testable import ChargePlanCore

final class ChargePlanTests: XCTestCase {
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
        XCTAssertTrue(cfg.deadbandEnabled)
        XCTAssertEqual(cfg.deadbandDelta, 3)
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
            deadbandEnabled: false,
            deadbandDelta: 5,
            thermalProtectionEnabled: true,
            autoServerMode: false,
            pollIntervalSeconds: 10.0
        )
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(GovernorConfig.self, from: data)
        XCTAssertEqual(decoded.targetLimit, 80)
        XCTAssertFalse(decoded.deadbandEnabled)
        XCTAssertEqual(decoded.deadbandDelta, 5)
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
    
    func testUpdateSemverComparison() {
        XCTAssertEqual(UpdateChecker.compareVersion("0.2.0", "0.2.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersion("0.3.0", "0.2.0"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersion("0.2.0", "0.3.0"), .orderedAscending)
        XCTAssertEqual(UpdateChecker.compareVersion("v1.0.0", "0.9.9"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersion("0.2.1", "0.2.0"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersion("0.2", "0.2.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersion("1.0.0", "v1.0.0"), .orderedSame)
        
        XCTAssertTrue(UpdateChecker.isVersion("0.3.0", newerThan: "0.2.0"))
        XCTAssertFalse(UpdateChecker.isVersion("0.2.0", newerThan: "0.2.0"))
        XCTAssertFalse(UpdateChecker.isVersion("0.1.9", newerThan: "0.2.0"))
    }
    
    func testReleaseInfoSerialization() throws {
        let info = ReleaseInfo(
            version: "0.4.0",
            tagName: "v0.4.0",
            title: "ChargePlan 0.4.0",
            releaseNotes: "Feature update",
            htmlUrl: "https://github.com/wixe/chargeplan/releases/tag/v0.4.0",
            dmgUrl: "https://github.com/wixe/chargeplan/raw/main/dist/ChargePlan.dmg",
            binaryUrl: "https://raw.githubusercontent.com/wixe/chargeplan/main/bin/chargeplan",
            isNewer: true
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ReleaseInfo.self, from: data)
        XCTAssertEqual(decoded.version, "0.4.0")
        XCTAssertEqual(decoded.tagName, "v0.4.0")
        XCTAssertTrue(decoded.isNewer)
    }
}
