import Foundation
import XCTest
@testable import AeroSpatialCore

final class BusMemoryTests: XCTestCase {
    func testBudgetIsVisibleToSwiftAndRejectsExcessPayloads() throws {
        let bus = try SpatialBus(payloadBudgetBytes: 16)
        let reader = try XCTUnwrap(bus.subscribe(.head, latest: false))
        XCTAssertEqual(bus.publish(stream: .head, timestampNanoseconds: 1,
                                   payload: Data(repeating: 9, count: 8)), 0)
        XCTAssertEqual(bus.publish(stream: .head, timestampNanoseconds: 2,
                                   payload: Data(repeating: 7, count: 8)), 0)
        XCTAssertNotEqual(bus.publish(stream: .head, timestampNanoseconds: 3,
                                      payload: Data(repeating: 5, count: 1)), 0)
        let memory = try XCTUnwrap(bus.memoryStats())
        XCTAssertEqual(memory.limitBytes, 16)
        XCTAssertEqual(memory.liveBytes, 16)
        XCTAssertEqual(bus.stats(for: .head)?.budgetRejected, 1)
        XCTAssertEqual(try reader.next()?.sequence, 1)
        XCTAssertEqual(try reader.next()?.sequence, 2)
        XCTAssertNil(try reader.next())
    }

    func testRejectInvalidGlobalBudget() {
        XCTAssertThrowsError(try SpatialBus(payloadBudgetBytes: 0))
    }
}
