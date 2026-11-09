import XCTest
@testable import AeroSpatialCore

final class CompactHeadTests: XCTestCase {
    func testCompactCodecAndTransport() throws {
        let sample = HeadSample(uptime: 12.25,
                                pose: HeadPose(yaw: 10, pitch: -20, roll: 5))
        let encoded = try XCTUnwrap(CompactHeadCodec.encode(sample))
        XCTAssertEqual(encoded.count, 44)
        XCTAssertEqual(CompactHeadCodec.decode(encoded), sample)
        var corrupted = encoded
        corrupted[16] ^= 1
        XCTAssertNil(CompactHeadCodec.decode(corrupted))
        let bus = try SpatialBus()
        let subscription = try XCTUnwrap(bus.subscribe(.head, latest: false))
        XCTAssertTrue(bus.publishCompact(head: sample))
        let event = try XCTUnwrap(subscription.next())
        XCTAssertEqual(event.kind, CompactHeadCodec.messageKind)
        XCTAssertEqual(CompactHeadCodec.decode(event.payload), sample)
    }
}
