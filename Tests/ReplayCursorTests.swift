import XCTest
@testable import AeroSpatialCore

final class ReplayCursorTests: XCTestCase {
    private func records() -> [SessionRecord] {
        (0..<20).map { index in
            SessionRecord(uptime: Double(index) * 0.5,
                          kind: "head", source: "simulator", fields: ["yaw": Double(index)])
        }
    }

    func testStepAndSeekAreDeterministic() throws {
        var replay = try ReplayCursor(records: records())
        XCTAssertEqual(replay.count, 20)
        XCTAssertEqual(replay.advance(through: 1.1).count, 3)
        XCTAssertEqual(replay.nextUptime, 1.5)
        try replay.seek(to: 0.5)
        XCTAssertEqual(replay.advance(through: 1.5).count, 3)
        replay.reset()
        XCTAssertEqual(replay.nextUptime, 0)
    }

    func testBoundedDeliveryAndInvalidSeek() throws {
        var replay = try ReplayCursor(records: records())
        XCTAssertEqual(replay.advance(through: 100, maxCount: 4).count, 4)
        XCTAssertEqual(replay.remainingCount, 16)
        XCTAssertThrowsError(try replay.seek(to: .nan))
    }

    func testInvalidRecordingCannotBePlayed() {
        let bad = [SessionRecord(uptime: 3, kind: "a", source: "test"),
                   SessionRecord(uptime: 1, kind: "b", source: "test")]
        XCTAssertThrowsError(try ReplayCursor(records: bad))
    }
}
