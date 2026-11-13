import Foundation
import XCTest
@testable import AeroSpatialCore

final class AccessUnitAndQueueTests: XCTestCase {
    func testAccessUnitAcrossChunkBoundaries() throws {
        let parser = try XCTUnwrap(H264AccessUnitAssembler(maximumNALBytes: 128, maximumAccessUnitBytes: 256))
        let bytes = Data([0, 0, 1, 0x67, 0x42, 0, 0x1f,
                          0, 0, 1, 0x68, 0xce, 0x3c,
                          0, 0, 1, 0x65, 0x80, 0x55,
                          0, 0, 1, 0x41, 0x80, 0x66,
                          0, 0, 1, 0x09, 0xf0])
        var collected: [H264AccessUnit] = []
        for byte in bytes { collected += try parser.accept(Data([byte])) }
        collected += try parser.finish()
        XCTAssertEqual(collected.count, 2)
        XCTAssertTrue(collected[0].isKeyframe)
        XCTAssertFalse(collected[1].isKeyframe)
        XCTAssertEqual(collected[0].sps, Data([0x67, 0x42, 0, 0x1f]))
        XCTAssertEqual(collected[0].avcc.prefix(4), Data([0, 0, 0, 3]))
        parser.reset()
        XCTAssertTrue(try parser.accept(Data([0, 0, 1, 0x41, 0x80, 0, 0, 1, 9, 0xf0])).isEmpty)
        XCTAssertTrue(try parser.finish().isEmpty)
    }

    func testNativeQueuePriorityAndExpiration() throws {
        let queue = try XCTUnwrap(NativeWorkQueue(maximumEvents: 2,
                                                  maximumBytes: 16,
                                                  maximumPayloadBytes: 8))
        func work(_ id: UInt64, _ priority: NativeWorkQueue.Priority,
                  _ limit: UInt64 = 100) -> NativeWorkQueue.Work {
            .init(traceID: id, receivedNanoseconds: 1, deadlineNanoseconds: limit,
                  kind: 1, priority: priority, payload: Data([1, 2]))
        }
        XCTAssertEqual(queue.push(work(1, .optional), at: 2), .accepted)
        XCTAssertEqual(queue.push(work(2, .optional), at: 2), .accepted)
        XCTAssertEqual(queue.push(work(3, .essential), at: 2), .accepted)
        XCTAssertEqual(queue.report()?.evicted_optional, 1)
        XCTAssertEqual(queue.pop(at: 3)?.traceID, 3)
        XCTAssertEqual(queue.pop(at: 3)?.traceID, 2)
        XCTAssertNil(queue.pop(at: 3))
        XCTAssertEqual(queue.push(work(4, .optional, 5), at: 2), .accepted)
        XCTAssertNil(queue.pop(at: 5))
        XCTAssertEqual(queue.report()?.expired, 1)
        queue.close()
        XCTAssertEqual(queue.push(work(5, .optional), at: 3), .closed)
    }
}
