import XCTest
@testable import AeroSpatialCore

final class AdvisorTests: XCTestCase {
    private func snapshot(time: Double, connected: Bool = true,
                          flying: Bool = true, battery: Int = 80) -> AircraftSnapshot {
        AircraftSnapshot(uptime: time, source: .simulator,
                         connected: connected, flying: flying, batteryPercent: battery)
    }

    func testCrossingThresholdDoesNotSpam() {
        var advisor = PassiveAdvisor()
        XCTAssertTrue(advisor.observe(snapshot(time: 1, battery: 40)).isEmpty)
        XCTAssertEqual(advisor.observe(snapshot(time: 2, battery: 24)).map(\.code), ["battery_low"])
        XCTAssertTrue(advisor.observe(snapshot(time: 3, battery: 23)).isEmpty)
        XCTAssertEqual(advisor.observe(snapshot(time: 4, battery: 12)).map(\.code), ["battery_critical"])
        XCTAssertTrue(advisor.observe(snapshot(time: 5, battery: 11)).isEmpty)
    }

    func testBatteryHysteresisPreventsRepeatedWarnings() {
        var advisor = PassiveAdvisor()
        XCTAssertEqual(advisor.observe(snapshot(time: 1, battery: 24)).map(\.code), ["battery_low"])
        XCTAssertTrue(advisor.observe(snapshot(time: 2, battery: 26)).isEmpty)
        XCTAssertTrue(advisor.observe(snapshot(time: 3, battery: 24)).isEmpty)
        XCTAssertTrue(advisor.observe(snapshot(time: 4, battery: 29)).isEmpty)
        XCTAssertEqual(advisor.observe(snapshot(time: 5, battery: 24)).map(\.code), ["battery_low"])
    }

    func testLinkLossAndWatchdog() {
        var advisor = PassiveAdvisor()
        _ = advisor.observe(snapshot(time: 1))
        XCTAssertEqual(advisor.observe(snapshot(time: 2, connected: false)).map(\.code), ["link_lost"])
        XCTAssertTrue(advisor.observe(snapshot(time: 3, connected: false)).isEmpty)
        XCTAssertNil(advisor.checkTelemetryAge(lastSnapshotUptime: 3, now: 4))
        XCTAssertEqual(advisor.checkTelemetryAge(lastSnapshotUptime: 3, now: 6)?.code,
                       "telemetry_stale")
        XCTAssertNil(advisor.checkTelemetryAge(lastSnapshotUptime: 3, now: 7))
        XCTAssertNil(advisor.checkTelemetryAge(lastSnapshotUptime: 7, now: 7.1))
    }
}
