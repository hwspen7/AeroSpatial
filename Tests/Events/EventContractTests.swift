import XCTest
@testable import AeroSpatialCore

final class EventContractTests: XCTestCase {
    func testRejectsMalformedEvents() {
        let sample = SessionRecord(uptime: 10, kind: "telemetry", source: "dji",
                                   fields: ["sensor_uptime": 9.9])
        XCTAssertTrue(EventContract.accepts(sample))
        var invalid = sample
        invalid.fields["pitch"] = .infinity
        XCTAssertFalse(EventContract.accepts(invalid))
        invalid = sample
        invalid.note = String(repeating: "x", count: 4097)
        XCTAssertFalse(EventContract.accepts(invalid))
        invalid = sample
        invalid.kind = "telemetry/../bad"
        XCTAssertFalse(EventContract.accepts(invalid))
        invalid = sample
        invalid.schemaVersion = 1
        XCTAssertFalse(EventContract.accepts(invalid))
        invalid = sample
        invalid.uptime = -1
        XCTAssertFalse(EventContract.accepts(invalid))
    }

    func testScenarioProducesContractCompatibleEvents() throws {
        let events = try ScenarioRunner.generate(.init(durationSeconds: 2))
        XCTAssertTrue(events.allSatisfy(EventContract.accepts))
    }
}
