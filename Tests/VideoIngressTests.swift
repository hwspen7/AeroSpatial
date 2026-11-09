import XCTest
@testable import AeroSpatialCore

final class VideoIngressTests: XCTestCase {
    func testVideoPathAndClockConstraints() throws {
        let bus = try SpatialBus()
        let reader = try XCTUnwrap(bus.subscribe(.video, latest: false))
        var ingress = VideoIngress()
        let packet = Data([0, 0, 1, 0x67, 0xff])
        let frame = try XCTUnwrap(EncodedFrame(bytes: packet, codec: .h264,
            timestampNanoseconds: 100, clockDomain: 3, traceID: 42, estimatedClock: true))
        XCTAssertTrue(ingress.publish(frame, to: bus))
        let event = try XCTUnwrap(reader.next())
        XCTAssertEqual(event.traceID, 42)
        XCTAssertTrue(event.quality.contains(.clockEstimated))
        XCTAssertFalse(ingress.publish(try XCTUnwrap(EncodedFrame(bytes: packet, codec: .h264,
            timestampNanoseconds: 90, clockDomain: 3, traceID: 43)), to: bus))
        XCTAssertFalse(ingress.publish(try XCTUnwrap(EncodedFrame(bytes: packet, codec: .h264,
            timestampNanoseconds: 101, clockDomain: 4, traceID: 43)), to: bus))
        XCTAssertEqual(ingress.accepted, 1)
        XCTAssertEqual(ingress.rejected, 2)
        XCTAssertNil(EncodedFrame(bytes: Data(), codec: .h264, timestampNanoseconds: 3,
                                  clockDomain: 1, traceID: 0))
    }
}
