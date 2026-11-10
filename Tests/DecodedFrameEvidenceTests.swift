import Foundation
import XCTest
@testable import AeroSpatialCore

final class DecodedFrameEvidenceTests: XCTestCase {
    func testRejectsInvalidOutOfOrderAndStaleReceipts() {
        let monitor = DecodedFrameEvidence(maximumAgeNanoseconds: 100)
        XCTAssertFalse(monitor.record(width: 0, height: 120, receivedAtNanoseconds: 10, decodedAtNanoseconds: 20))
        XCTAssertFalse(monitor.record(width: 128, height: 120, receivedAtNanoseconds: 30, decodedAtNanoseconds: 20))
        XCTAssertTrue(monitor.record(width: 128, height: 120, receivedAtNanoseconds: 40, decodedAtNanoseconds: 60))
        XCTAssertFalse(monitor.record(width: 128, height: 120, receivedAtNanoseconds: 39, decodedAtNanoseconds: 60))
        XCTAssertFalse(monitor.record(width: 128, height: 120, receivedAtNanoseconds: 70, decodedAtNanoseconds: 190))
        XCTAssertTrue(monitor.record(width: 192, height: 108, receivedAtNanoseconds: 80, decodedAtNanoseconds: 110))
        let report = monitor.snapshot()
        XCTAssertEqual(report.accepted, 2)
        XCTAssertEqual(report.invalid, 2)
        XCTAssertEqual(report.outOfOrder, 1)
        XCTAssertEqual(report.stale, 1)
        XCTAssertEqual(report.width, 192)
        XCTAssertEqual(report.maximumReceiptToDecodeNanoseconds, 30)
        monitor.reset()
        XCTAssertEqual(monitor.snapshot().accepted, 0)
    }

    func testConcurrentSnapshotAndRecord() async {
        let monitor = DecodedFrameEvidence()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<8 {
                group.addTask {
                    for j in 0..<100 {
                        _ = monitor.record(width: 64, height: 64,
                            receivedAtNanoseconds: UInt64(1000 + i * 100 + j),
                            decodedAtNanoseconds: UInt64(1001 + i * 100 + j))
                        _ = monitor.snapshot()
                    }
                }
            }
        }
        let report = monitor.snapshot()
        XCTAssertEqual(report.accepted + report.invalid + report.outOfOrder + report.stale, 800)
    }
}
