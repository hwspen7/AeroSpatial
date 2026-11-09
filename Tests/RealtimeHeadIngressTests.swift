import XCTest
@testable import AeroSpatialCore

final class RealtimeHeadIngressTests: XCTestCase {
    func testBoundedIngressAndCoalescing() {
        let queue = RealtimeHeadIngress(capacity: 3)!
        for number in 0..<3 {
            XCTAssertTrue(queue.offer(HeadSample(uptime: Double(number),
                pose: HeadPose(yaw: Double(number), pitch: 0, roll: 0))))
        }
        XCTAssertFalse(queue.offer(HeadSample(uptime: 9,
            pose: HeadPose(yaw: 9, pitch: 0, roll: 0))))
        XCTAssertEqual(queue.takeLatest()?.pose.yaw, 2)
        XCTAssertNil(queue.takeLatest())
        XCTAssertEqual(queue.counters?.accepted, 3)
        XCTAssertEqual(queue.counters?.coalesced, 2)
        XCTAssertEqual(queue.counters?.full, 1)
    }

    func testRejectNonFinite() {
        let queue = RealtimeHeadIngress()!
        XCTAssertFalse(queue.offer(HeadSample(uptime: .nan,
            pose: HeadPose(yaw: 0, pitch: 0, roll: 0))))
        XCTAssertEqual(queue.counters?.invalid, 1)
    }
}
