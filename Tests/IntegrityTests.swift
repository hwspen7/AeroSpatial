import XCTest
@testable import AeroSpatialCore

final class IntegrityTests: XCTestCase {
    func testVersionedRecordRoundTrip() throws {
        let record = SessionRecord(
            wallTime: Date(timeIntervalSince1970: 1_700_000_000), uptime: 123, kind: "head", source: "airpods", fields: ["yaw": 15],
            schemaVersion: 1, sessionId: "example", sequence: 0)
        let parsed = try SessionReplay.decodeJSONL(SessionReplay.encodeJSONL([record]))
        XCTAssertEqual(parsed, [record])
        XCTAssertEqual(SessionIntegrity.inspect(parsed).issueCount, 0)
    }

    func testIntegrityIdentifiesSequenceGap() {
        let first = SessionRecord(uptime: 1, kind: "head", source: "simulator",
                                  schemaVersion: 1, sessionId: "x", sequence: 0)
        let second = SessionRecord(uptime: 2, kind: "head", source: "simulator",
                                   schemaVersion: 1, sessionId: "x", sequence: 2)
        XCTAssertEqual(SessionIntegrity.inspect([first, second]).issueCount, 1)
    }
}
