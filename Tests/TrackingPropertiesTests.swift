import XCTest
@testable import AeroSpatialCore

final class TrackingPropertiesTests: XCTestCase {
    func testDeterministicJitterNeverExceedsPitchEnvelopeOrSlew() throws {
        var controller = HeadTrackingController()
        let reference = HeadSample(uptime: 100, pose: HeadPose(yaw: 0, pitch: 0, roll: 0))
        controller.calibrate(using: reference, currentGimbalPitch: -35)
        var previous: (time: Double, pitch: Double)?
        var seed: UInt64 = 0x12345678
        for step in 0..<1500 {
            seed = seed &* 6364136223846793005 &+ 1
            let unit = Double(seed >> 11) / Double(1 << 53)
            let time = 100 + Double(step) * 0.16
            let head = HeadSample(uptime: time, pose: HeadPose(
                yaw: 180 * unit, pitch: unit * 360 - 180, roll: 0))
            let decision = controller.update(sample: head, now: time,
                                             armed: true, aircraftConnected: true)
            let output = try XCTUnwrap(decision.pitchDegrees)
            XCTAssertGreaterThanOrEqual(output, -85)
            XCTAssertLessThanOrEqual(output, 0)
            if let previous = previous {
                XCTAssertLessThanOrEqual(abs(output - previous.pitch),
                                         20 * (time - previous.time) + 1e-6)
            }
            previous = (time, output)
        }
    }

    func testMalformedSettingsProduceNoCommand() {
        var controller = HeadTrackingController(settings: TrackingSettings(pitchGain: -.infinity))
        let sample = HeadSample(uptime: 1, pose: HeadPose(yaw: 0, pitch: 0, roll: 0))
        controller.calibrate(using: sample, currentGimbalPitch: -20)
        XCTAssertEqual(controller.update(sample: sample, now: 1, armed: true,
                                         aircraftConnected: true).status, .invalidInput)
    }
}
