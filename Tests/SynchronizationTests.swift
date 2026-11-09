import XCTest
@testable import AeroSpatialCore

final class SynchronizationTests: XCTestCase {
    private func sample(_ time: Double, yaw: Double) -> HeadSample {
        HeadSample(uptime: time, pose: HeadPose(yaw: yaw, pitch: 0, roll: 0))
    }

    func testHeadInterpolationRespectsWrap() {
        var sync = SensorSynchronizer()
        XCTAssertTrue(sync.append(sample(1.0, yaw: 179)))
        XCTAssertTrue(sync.append(sample(1.2, yaw: -179)))
        let result = sync.aligned(at: 1.1)
        XCTAssertTrue(result.interpolatedHead)
        XCTAssertEqual(Angle.signedDegrees(result.head?.yaw ?? .nan), -180, accuracy: 0.001)
    }

    func testOutOfOrderSamplesRejected() {
        var sync = SensorSynchronizer()
        XCTAssertTrue(sync.append(sample(2, yaw: 0)))
        XCTAssertFalse(sync.append(sample(1, yaw: 10)))
        XCTAssertEqual(sync.aligned(at: 2).head?.yaw, 0)
    }

    func testAircraftFreshnessAndNoFutureExtrapolation() {
        var sync = SensorSynchronizer(maximumAircraftAge: 1)
        let aircraft = AircraftSnapshot(uptime: 10, source: .simulator, connected: true, flying: false)
        sync.append(aircraft)
        XCTAssertNil(sync.aligned(at: 9.9).aircraft)
        XCTAssertNotNil(sync.aligned(at: 10.5).aircraft)
        XCTAssertNil(sync.aligned(at: 11.5).aircraft)
    }

    func testHeadExpires() {
        var sync = SensorSynchronizer(maximumHeadOffset: 0.2)
        sync.append(sample(1, yaw: 5))
        XCTAssertNotNil(sync.aligned(at: 1.1).head)
        XCTAssertNil(sync.aligned(at: 1.5).head)
    }

    func testResetDiscardsState() {
        var sync = SensorSynchronizer()
        sync.append(sample(1, yaw: 5))
        sync.reset()
        XCTAssertNil(sync.aligned(at: 1).head)
    }
}
