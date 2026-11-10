import Foundation
import XCTest
@testable import AeroSpatialCore

final class VideoPacketPublisherTests: XCTestCase {
    func testVideoFragmentUsesEstimatedReceiptClock() async throws {
        let bus = try SpatialBus()
        let subscription = try XCTUnwrap(bus.subscribe(.video, latest: true))
        let producer = VideoPacketPublisher(bus: bus, capacity: 4)
        XCTAssertTrue(producer.receive(Data([0, 0, 0, 1, 0x65, 0x88, 0, 0, 1, 0x67, 0x42]),
                                      receivedAtNanoseconds: 100))
        await producer.finish()
        let received = try XCTUnwrap(subscription.next())
        XCTAssertEqual(received.kind, VideoPacketPublisher.h264NALKindBase | 5)
        XCTAssertEqual(received.timestampNanoseconds, 100)
        XCTAssertEqual(received.payload, Data([0x65, 0x88]))
        XCTAssertTrue(received.quality.contains(.clockEstimated))
        XCTAssertTrue(received.quality.contains(.upstreamGap))
        XCTAssertFalse(producer.receive(Data([1]), receivedAtNanoseconds: 200))
    }

    func testInvalidDataAndDiscontinuity() async throws {
        let bus = try SpatialBus()
        let producer = VideoPacketPublisher(bus: bus)
        XCTAssertFalse(producer.receive(Data(), receivedAtNanoseconds: 1))
        XCTAssertFalse(producer.receive(Data([1]), receivedAtNanoseconds: 0))
        XCTAssertTrue(producer.receive(Data([1]), receivedAtNanoseconds: 100))
        XCTAssertFalse(producer.receive(Data([2]), receivedAtNanoseconds: 99))
        producer.markDiscontinuity()
        XCTAssertTrue(producer.receive(Data([3]), receivedAtNanoseconds: 101))
        let snapshot = producer.snapshot()
        XCTAssertEqual(snapshot.rejected, 3)
        XCTAssertEqual(snapshot.queued, 2)
        producer.close()
    }
}

final class H264UnitAssemblerTests: XCTestCase {
    func testSplitNALAndReset() throws {
        let parser = try XCTUnwrap(H264UnitAssembler(maximumNALBytes: 32))
        XCTAssertTrue(try parser.accept(Data([0, 0])).isEmpty)
        XCTAssertTrue(try parser.accept(Data([1, 0x67, 0x42, 0, 0])).isEmpty)
        let result = try parser.accept(Data([1, 0x68, 0xce, 0, 0, 1, 0x65, 0x88]))
        XCTAssertEqual(result.map(\.type), [7, 8])
        XCTAssertEqual(result[0].bytes, Data([0x67, 0x42]))
        parser.reset()
        XCTAssertTrue(try parser.accept(Data([0, 0, 1, 0x65])).isEmpty)
        XCTAssertThrowsError(try parser.accept(Data(repeating: 0x55, count: 32)))
    }
}

private final class AccessUnitSink: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [H264AccessUnit] = []
    func collect(_ value: H264AccessUnit) {
        lock.lock()
        items.append(value)
        lock.unlock()
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }
}

final class VideoAccessIntegrationTests: XCTestCase {
    func testNativeVideoQueueDeliversCompleteAccessUnits() async throws {
        let bus = try SpatialBus()
        let observer = AccessUnitSink()
        let publisher = VideoPacketPublisher(bus: bus, capacity: 4,
            onAccessUnit: { unit, _, _ in observer.collect(unit) })
        let stream = Data([0, 0, 1, 0x67, 0x42, 0, 0x1f,
                           0, 0, 1, 0x68, 0xce, 0x3c,
                           0, 0, 1, 0x65, 0x80, 0x55,
                           0, 0, 1, 0x41, 0x80, 0x66,
                           0, 0, 1, 0x09, 0xf0, 0, 0, 1, 0x09, 0xf0])
        XCTAssertTrue(publisher.receive(stream, receivedAtNanoseconds: 50))
        await publisher.finish()
        XCTAssertEqual(observer.count, 2)
        XCTAssertEqual(publisher.snapshot().accessUnits, 2)
        XCTAssertEqual(publisher.snapshot().assemblyFailures, 0)
        XCTAssertEqual(publisher.snapshot().nativeRejected, 0)
    }
}
