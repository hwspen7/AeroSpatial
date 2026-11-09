import XCTest
@testable import AeroSpatialCore

final class RuntimeTests: XCTestCase {
    func testRingWrapAndBinaryLookup() {
        var ring = TimestampRing<Double>(capacity: 4)
        (0..<20).forEach { ring.append(Double($0)) }
        XCTAssertEqual(ring.count, 4)
        XCTAssertEqual(ring[0], 16)
        XCTAssertEqual(ring[3], 19)
        XCTAssertEqual(ring.lowerBound(time: 17.5, timestamp: { $0 }), 2)
        XCTAssertEqual(ring.upperBound(time: 18, timestamp: { $0 }), 3)
    }

    func testSynchronizerAfterWrapAndWrapAngle() {
        var sync = SensorSynchronizer(capacity: 4, maximumHeadOffset: 0.6)
        for index in 0..<50 {
            XCTAssertTrue(sync.append(HeadSample(uptime: Double(index),
                pose: HeadPose(yaw: index == 48 ? 179 : index == 49 ? -179 : 0,
                               pitch: Double(index), roll: 0))))
        }
        let output = sync.aligned(at: 48.5)
        XCTAssertTrue(output.interpolatedHead)
        XCTAssertEqual(abs(output.head!.yaw), 180, accuracy: 0.00001)
        XCTAssertEqual(output.head!.pitch, 48.5, accuracy: 0.00001)
        XCTAssertNil(sync.aligned(at: 35).head)
    }

    func testGovernorPrioritizesImportantUpdates() {
        var governor = StreamGovernor()
        XCTAssertTrue(governor.shouldPublish(at: 1))
        XCTAssertFalse(governor.shouldPublish(at: 1.001))
        XCTAssertTrue(governor.shouldPublish(at: 1.002, important: true))
        for _ in 0..<50 { governor.observeProcessing(seconds: 0.10, backlogged: true) }
        XCTAssertEqual(governor.interval, 0.25, accuracy: 0.00001)
        XCTAssertFalse(governor.shouldPublish(at: 1.1))
        XCTAssertTrue(governor.shouldPublish(at: 1.3))
        XCTAssertEqual(governor.skippedCount, 2)
    }

    func testClockBridgeRejectsOutliersWithoutCorruptingMapping() {
        var bridge = ClockBridge()
        XCTAssertEqual(bridge.observe(remote: 10, local: 13), .accepted)
        XCTAssertEqual(bridge.observe(remote: 11, local: 14), .accepted)
        XCTAssertEqual(bridge.observe(remote: 12, local: 18), .rejectedOutlier)
        XCTAssertEqual(bridge.translate(remote: 12)!, 15, accuracy: 0.0001)
        XCTAssertEqual(bridge.count, 2)
        XCTAssertEqual(bridge.observe(remote: 10.5, local: 13.5), .rejectedNonMonotonic)
    }
}

extension RuntimeTests {
    func testBoundedBufferMatchesReferenceAcrossWraps() {
        let size = 32
        var buffer = TimestampRing<Double>(capacity: size)
        var reference: [Double] = []
        for index in 0..<1000 {
            let value = Double(index) * 0.01
            buffer.append(value)
            reference.append(value)
            if reference.count > size { reference.removeFirst() }
            if index % 9 != 0 { continue }
            for j in 0...32 {
                let query = value - Double(j) * 0.015
                XCTAssertEqual(buffer.lowerBound(time: query) { $0 },
                               reference.firstIndex(where: { $0 >= query }) ?? reference.count)
                XCTAssertEqual(buffer.upperBound(time: query) { $0 },
                               reference.firstIndex(where: { $0 > query }) ?? reference.count)
            }
        }
    }

    func testClockBridgeRejectsInvalidObservations() {
        var bridge = ClockBridge()
        XCTAssertEqual(bridge.observe(remote: .infinity, local: 1), .invalid)
        XCTAssertNil(bridge.translate(remote: 100))
        XCTAssertEqual(bridge.observe(remote: 1, local: 2), .accepted)
        XCTAssertEqual(bridge.observe(remote: 1, local: 2), .rejectedNonMonotonic)
        XCTAssertNil(bridge.translate(remote: -.infinity))
        XCTAssertEqual(bridge.count, 1)
    }
}
