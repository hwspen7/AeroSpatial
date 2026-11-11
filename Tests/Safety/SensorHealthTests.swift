import XCTest
@testable import AeroSpatialCore

final class SensorHealthTests: XCTestCase {
    func testDropsOutOfOrderAndStaleness() {
        var monitor = SensorHealthMonitor()
        func head(_ t: Double) -> HeadSample {
            HeadSample(uptime: t, pose: HeadPose(yaw: 0, pitch: 0, roll: 0))
        }
        XCTAssertEqual(monitor.observeHead(head(10), receivedAt: 10), .accepted)
        XCTAssertEqual(monitor.observeHead(head(10), receivedAt: 10.1), .outOfOrder)
        XCTAssertEqual(monitor.observeHead(head(10.1), receivedAt: 10.1), .accepted)
        XCTAssertEqual(monitor.observeHead(head(10.5), receivedAt: 10.5), .accepted)
        XCTAssertEqual(monitor.observeHead(head(15), receivedAt: 10.5), .futureTimestamp)
        let stats = monitor.health(at: 10.6).head
        XCTAssertEqual(stats.accepted, 3)
        XCTAssertEqual(stats.rejected, 2)
        XCTAssertEqual(stats.observedGaps, 1)
        XCTAssertEqual(stats.freshness, .fresh)
        XCTAssertEqual(monitor.health(at: 11).head.freshness, .stale)
        XCTAssertEqual(monitor.health(at: 11).aircraft.freshness, .missing)
    }

    func testInvalidAircraftAndReset() {
        var monitor = SensorHealthMonitor()
        let sample = AircraftSnapshot(uptime: 1, source: .simulator, connected: true,
                                      flying: false, batteryPercent: 130)
        XCTAssertEqual(monitor.observeAircraft(sample, receivedAt: 1), .invalid)
        XCTAssertEqual(monitor.health(at: 1).aircraft.rejected, 1)
        monitor.reset()
        XCTAssertEqual(monitor.health(at: 1).aircraft.rejected, 0)
    }
}
