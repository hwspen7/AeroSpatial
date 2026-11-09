import XCTest
@testable import AeroSpatialCore

final class ReplayTests: XCTestCase {
    func testRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            SessionRecord(wallTime: now, uptime: 10, kind: "head", source: "airpods", fields: ["yaw": 25]),
            SessionRecord(wallTime: now.addingTimeInterval(1), uptime: 11,
                          kind: "gimbal", source: "simulator", fields: ["pitch": -30])
        ]
        let payload = try SessionReplay.encodeJSONL(records)
        XCTAssertEqual(try SessionReplay.decodeJSONL(payload), records)
        let summary = SessionReplay.summarize(records)
        XCTAssertEqual(summary.totalRecords, 2)
        XCTAssertEqual(summary.durationSeconds, 1)
        XCTAssertEqual(summary.recordsByKind["head"], 1)
        XCTAssertEqual(summary.nonmonotonicRecords, 0)
    }

    func testCorruptLineIdentifiesLineNumber() {
        let data = Data("\nnot valid json\n".utf8)
        XCTAssertThrowsError(try SessionReplay.decodeJSONL(data)) { error in
            XCTAssertEqual(error as? ReplayError, .invalidJSONLine(2))
        }
    }

    func testOutOfOrderDetected() {
        let records = [SessionRecord(uptime: 11, kind: "a", source: "test"),
                       SessionRecord(uptime: 10, kind: "b", source: "test")]
        XCTAssertEqual(SessionReplay.summarize(records).nonmonotonicRecords, 1)
    }
}
