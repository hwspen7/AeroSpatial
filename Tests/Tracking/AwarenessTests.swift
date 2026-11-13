import XCTest
@testable import AeroSpatialCore

final class AwarenessTests: XCTestCase {
    private func head(_ time: Double, _ yaw: Double) -> HeadSample {
        HeadSample(uptime: time, pose: HeadPose(yaw: yaw, pitch: 0, roll: 0))
    }

    func testHeadRelativeCueAndCalibrationExpiry() throws {
        let calibration = try XCTUnwrap(CompassCalibration(
            sample: head(100, 15), heading: 0, headingAccuracy: 5))
        var awareness = HeadRelativeAwareness()
        awareness.setCalibration(calibration)
        let origin = GeoPoint(latitude: 0, longitude: 0)
        let east = GeoPoint(latitude: 0, longitude: 0.001)
        let cue = try XCTUnwrap(awareness.cue(head: head(101, 105), now: 101.1,
                                              pilot: origin, pilotFixUptime: 101,
                                              target: east, targetFixUptime: 101))
        XCTAssertEqual(cue.relativeBearingDegrees, 0, accuracy: 0.01)
        XCTAssertEqual(cue.approximateDirection, "Ahead")
        XCTAssertNil(awareness.cue(head: head(221, 105), now: 221,
                                  pilot: origin, pilotFixUptime: 221,
                                  target: east, targetFixUptime: 221))
        awareness.reset()
        XCTAssertNil(awareness.calibration)
    }

    func testRejectsCompassUncertaintyAndStaleSamples() throws {
        XCTAssertNil(CompassCalibration(sample: head(1, 0), heading: 0, headingAccuracy: 30))
        var awareness = HeadRelativeAwareness()
        awareness.setCalibration(try XCTUnwrap(CompassCalibration(
            sample: head(1, 0), heading: 0, headingAccuracy: 1)))
        let point = GeoPoint(latitude: 0, longitude: 0)
        XCTAssertNil(awareness.cue(head: head(1, 0), now: 2,
                                   pilot: point, pilotFixUptime: 2,
                                   target: point, targetFixUptime: 2))
    }

    func testCapabilityStartsUnverifiedAndBlocksFlight() {
        XCTAssertFalse(DeviceCapabilities.unverifiedDJI.allowsPitchCommand(
            connected: true, hardwareVerified: false))
        XCTAssertTrue(DeviceCapabilities.simulator.allowsPitchCommand(
            connected: true, hardwareVerified: false))
        XCTAssertFalse(DeviceCapabilities.simulator.canCommandFlight)
    }
}
