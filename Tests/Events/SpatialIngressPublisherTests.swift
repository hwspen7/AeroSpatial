import Foundation
import XCTest
@testable import AeroSpatialCore

final class SpatialIngressPublisherTests: XCTestCase {
    func testBoundedIngressAndDrain() async throws {
        let bus = try SpatialBus()
        let reader = try XCTUnwrap(bus.subscribe(.head, latest: true))
        let publisher = SpatialIngressPublisher(bus: bus, capacity: 4)
        let first = HeadSample(uptime: 1.0, pose: HeadPose(yaw: 1, pitch: 2, roll: 3))
        XCTAssertTrue(publisher.send(head: first, simulated: true))
        await publisher.finish()
        let metrics = publisher.snapshot()
        XCTAssertEqual(metrics.queued, 1)
        XCTAssertEqual(metrics.published, 1)
        XCTAssertEqual(metrics.nativeRejected, 0)
        let event = try XCTUnwrap(reader.next())
        XCTAssertTrue(event.quality.contains(.simulated))
        XCTAssertFalse(publisher.send(head: first))
        XCTAssertEqual(publisher.snapshot().rejected, 1)
    }
}
