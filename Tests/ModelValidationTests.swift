import XCTest
@testable import AeroSpatialCore

final class ModelValidationTests: XCTestCase {
    func testNonFiniteAircraftTelemetryRejected() {
        let corrupt = AircraftSnapshot(
            uptime: 4, source: .dji, connected: true, flying: true,
            position: GeoPoint(latitude: 91, longitude: 0),
            gimbalPitchDegrees: .nan, batteryPercent: 101)
        XCTAssertFalse(corrupt.isValid)
        var synchronizer = SensorSynchronizer()
        XCTAssertFalse(synchronizer.append(corrupt))
        XCTAssertNil(synchronizer.aligned(at: 4.1).aircraft)
    }

    func testValidAircraftTelemetryAccepted() {
        let snapshot = AircraftSnapshot(
            uptime: 5, source: .simulator, connected: true, flying: false,
            position: GeoPoint(latitude: 40, longitude: -83),
            gimbalPitchDegrees: -20, batteryPercent: 87)
        var synchronizer = SensorSynchronizer()
        XCTAssertTrue(synchronizer.append(snapshot))
        XCTAssertEqual(synchronizer.aligned(at: 5.2).aircraft, snapshot)
    }
}
