import XCTest
@testable import AeroSpatialCore

final class SpatialBusTests: XCTestCase {
    func testIndependentSubscribersAndGapAccounting() throws {
        let bus = try SpatialBus()
        let slow = try XCTUnwrap(bus.subscribe(.head, latest: false))
        let fast = try XCTUnwrap(bus.subscribe(.head, latest: true))
        for i in 0..<300 {
            XCTAssertEqual(bus.publish(stream: .head, timestampNanoseconds: UInt64(i),
                                       payload: Data([UInt8(i % 256)])), 0)
        }
        let first = try XCTUnwrap(slow.next())
        XCTAssertEqual(first.sequence, 45)
        XCTAssertEqual(first.missed, 44)
        XCTAssertEqual(first.payload, Data([44]))
        let another = try XCTUnwrap(fast.next())
        XCTAssertEqual(another.sequence, 45)
        XCTAssertEqual(another.missed, 44)
        XCTAssertEqual(bus.stats(for: .head)?.overwritten, 44)
    }

    func testVideoHasSeparateLimitsAndClockDomain() throws {
        let bus = try SpatialBus()
        let reader = try XCTUnwrap(bus.subscribe(.video, latest: false))
        XCTAssertTrue(bus.publishEncodedVideo(Data(repeating: 7, count: 1024),
                                              timestampNanoseconds: 9, clockDomain: 2,
                                              codec: 7, traceID: 88))
        let message = try XCTUnwrap(reader.next())
        XCTAssertEqual(message.payload.count, 1024)
        XCTAssertEqual(message.clockDomain, 2)
        XCTAssertEqual(message.kind, 7)
        XCTAssertEqual(message.traceID, 88)
        XCTAssertFalse(bus.publishEncodedVideo(Data(repeating: 1, count: 2_097_153),
                                               timestampNanoseconds: 10, clockDomain: 2, codec: 7))
    }

    func testTypedSourcesAndQualityFlags() throws {
        let bus = try SpatialBus()
        let headSub = try XCTUnwrap(bus.subscribe(.head, latest: false))
        let aircraftSub = try XCTUnwrap(bus.subscribe(.telemetry, latest: false))
        let head = HeadSample(uptime: 3.25, pose: HeadPose(yaw: 10, pitch: -20, roll: 5))
        XCTAssertTrue(bus.publish(head: head, simulated: true))
        let aircraft = AircraftSnapshot(uptime: 3.5, source: .simulator,
                                        connected: true, flying: false, batteryPercent: 99)
        XCTAssertTrue(bus.publish(aircraft: aircraft))
        let h = try XCTUnwrap(headSub.next())
        XCTAssertTrue(h.quality.contains(.simulated))
        XCTAssertEqual(try JSONDecoder().decode(HeadSample.self, from: h.payload), head)
        let t = try XCTUnwrap(aircraftSub.next())
        XCTAssertEqual(try JSONDecoder().decode(AircraftSnapshot.self, from: t.payload), aircraft)
    }

    func testInvalidDataCannotPoisonSequence() throws {
        let bus = try SpatialBus()
        let reader = try XCTUnwrap(bus.subscribe(.perception, latest: false))
        XCTAssertEqual(bus.publish(stream: .perception, timestampNanoseconds: 100,
                                   payload: Data()), 0)
        XCTAssertNotEqual(bus.publish(stream: .perception, timestampNanoseconds: 99,
                                      payload: Data()), 0)
        XCTAssertNotEqual(bus.publish(stream: .perception, timestampNanoseconds: 101,
                                      clockDomain: 0, payload: Data()), 0)
        XCTAssertEqual(bus.publish(stream: .perception, timestampNanoseconds: 101,
                                   payload: Data()), 0)
        XCTAssertEqual(try reader.next()?.sequence, 1)
        XCTAssertEqual(try reader.next()?.sequence, 2)
        XCTAssertNil(try reader.next())
    }

    func testInvalidTimestampsAndZeroBytePayload() throws {
        XCTAssertNil(SpatialBus.uptimeNanoseconds(.nan))
        XCTAssertNil(SpatialBus.uptimeNanoseconds(-0.1))
        XCTAssertEqual(SpatialBus.uptimeNanoseconds(0.5), 500_000_000)
        let bus = try SpatialBus()
        let reader = try XCTUnwrap(bus.subscribe(.perception, latest: false))
        XCTAssertTrue(bus.publishPerception(Data(), timestampNanoseconds: 0,
                                            clockDomain: 1, modelID: 1))
        XCTAssertEqual(try reader.next()?.payload.count, 0)
    }
}
