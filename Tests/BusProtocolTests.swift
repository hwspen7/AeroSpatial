import Foundation
import XCTest
@testable import AeroSpatialCore

final class BusProtocolTests: XCTestCase {
    func testVersionedEnvelopePreservesProvenance() throws {
        let bus = try SpatialBus()
        let reader = try XCTUnwrap(bus.subscribe(.diagnostic, latest: false))
        XCTAssertEqual(bus.publish(stream: .diagnostic, timestampNanoseconds: 120,
                                   clockDomain: 4, traceID: 47, payload: Data([1, 2])), 0)
        let event = try XCTUnwrap(reader.next())
        let record = SpatialBusEnvelopeExtended(event, upstreamMissing: 2,
                                                sampled: 4, rejected: 1,
                                                alignedNs: 121, uncertaintyNs: 3)
        let bytes = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SpatialBusEnvelopeExtended.self, from: bytes)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.upstreamMissing, 2)
        XCTAssertEqual(decoded.traceId, 47)
    }
}
