import XCTest
@testable import AeroSpatialCore

final class TrackingTests: XCTestCase {
    private func sample(_ time: Double, _ pitch: Double, yaw: Double = 0) -> HeadSample {
        HeadSample(uptime: time, pose: HeadPose(yaw: yaw, pitch: pitch, roll: 0))
    }

    func testDisarmedNeverProducesCommand() {
        var controller = HeadTrackingController()
        controller.calibrate(using: sample(1, 0), currentGimbalPitch: -30)
        let result = controller.update(sample: sample(1.1, 30), now: 1.1, armed: false, aircraftConnected: true)
        XCTAssertEqual(result.status, .disarmed)
        XCTAssertNil(result.pitchDegrees)
    }

    func testDisconnectNeverProducesCommand() {
        var controller = HeadTrackingController()
        controller.calibrate(using: sample(1, 0), currentGimbalPitch: -30)
        let result = controller.update(sample: sample(1.1, 20), now: 1.1, armed: true, aircraftConnected: false)
        XCTAssertEqual(result.status, .disconnected)
        XCTAssertNil(result.pitchDegrees)
    }

    func testCalibrationRequired() {
        var controller = HeadTrackingController()
        let result = controller.update(sample: sample(2, 0), now: 2, armed: true, aircraftConnected: true)
        XCTAssertEqual(result.status, .waitingForCalibration)
    }

    func testStaleHeadMotionNeverProducesCommand() {
        var controller = HeadTrackingController()
        controller.calibrate(using: sample(1, 0), currentGimbalPitch: -30)
        let result = controller.update(sample: sample(1, 30), now: 3, armed: true, aircraftConnected: true)
        XCTAssertEqual(result.status, .staleMotion)
        XCTAssertNil(result.pitchDegrees)
    }

    func testFutureTimestampsRejected() {
        var controller = HeadTrackingController()
        controller.calibrate(using: sample(1, 0), currentGimbalPitch: -30)
        let result = controller.update(sample: sample(100, 20), now: 1, armed: true, aircraftConnected: true)
        XCTAssertEqual(result.status, .staleMotion)
    }

    func testRateLimitEnforced() {
        var controller = HeadTrackingController()
        controller.calibrate(using: sample(1, 0), currentGimbalPitch: -30)
        XCTAssertEqual(controller.update(sample: sample(1, 0), now: 1, armed: true,
                                         aircraftConnected: true).status, .command)
        XCTAssertEqual(controller.update(sample: sample(1.05, 20), now: 1.05, armed: true,
                                         aircraftConnected: true).status, .rateLimited)
    }

    func testPitchOutputClampedAndSlewLimited() throws {
        var controller = HeadTrackingController()
        controller.calibrate(using: sample(1, 0), currentGimbalPitch: -30)
        let result = controller.update(sample: sample(1.02, 200), now: 1.02, armed: true, aircraftConnected: true)
        let pitch = try XCTUnwrap(result.pitchDegrees)
        XCTAssertGreaterThanOrEqual(pitch, -85)
        XCTAssertLessThanOrEqual(pitch, 0)
        XCTAssertLessThanOrEqual(abs(pitch + 30), 20 * 0.15 + 0.0001)
    }

    func testDeadZoneAndPitchInversion() throws {
        var controller = HeadTrackingController(settings: TrackingSettings(
            pitchGain: 1, invertPitch: true, deadZoneDegrees: 3, filterTimeConstant: 0,
            maximumPitchSpeed: 1000))
        controller.calibrate(using: sample(1, 0), currentGimbalPitch: -30)
        let inside = try XCTUnwrap(controller.update(sample: sample(1, 2), now: 1,
                                                     armed: true, aircraftConnected: true).pitchDegrees)
        XCTAssertEqual(inside, -30, accuracy: 0.0001)
        let outside = try XCTUnwrap(controller.update(sample: sample(1.2, 15), now: 1.2,
                                                      armed: true, aircraftConnected: true).pitchDegrees)
        XCTAssertEqual(outside, -42, accuracy: 0.0001)
    }

    func testWrapBoundaryDoesNotJump() throws {
        var controller = HeadTrackingController(settings: TrackingSettings(
            pitchGain: 1, deadZoneDegrees: 0, filterTimeConstant: 0,
            maximumPitchSpeed: 1000))
        controller.calibrate(using: sample(1, 179), currentGimbalPitch: -30)
        let pitch = try XCTUnwrap(controller.update(sample: sample(1, -179), now: 1,
                                                    armed: true, aircraftConnected: true).pitchDegrees)
        XCTAssertEqual(pitch, -28, accuracy: 0.0001)
    }

    func testResetRequiresRecalibration() {
        var controller = HeadTrackingController()
        controller.calibrate(using: sample(1, 0), currentGimbalPitch: -30)
        controller.reset()
        XCTAssertFalse(controller.calibrated)
        XCTAssertEqual(controller.update(sample: sample(1, 0), now: 1, armed: true,
                                         aircraftConnected: true).status, .waitingForCalibration)
    }

    func testNotANumberRejected() {
        var controller = HeadTrackingController()
        controller.calibrate(using: sample(1, 0), currentGimbalPitch: -30)
        XCTAssertEqual(controller.update(sample: sample(2, .nan), now: 2, armed: true,
                                         aircraftConnected: true).status, .invalidInput)
    }
}
