import XCTest
@testable import AeroSpatialCore

final class ScenarioTests: XCTestCase {
    func testReproducibleSyntheticControlLoop() throws {
        let config = ScenarioSettings(seed: 5, durationSeconds: 4)
        let left = try ScenarioRunner.generate(config)
        let right = try ScenarioRunner.generate(config)
        XCTAssertEqual(left, right)
        let different = try ScenarioRunner.generate(.init(seed: 6, durationSeconds: 4))
        XCTAssertNotEqual(left, different)
        XCTAssertEqual(SessionIntegrity.inspect(left).issueCount, 0)
        XCTAssertGreaterThan(left.filter { $0.kind == "gimbal_command" }.count, 2)
        XCTAssertEqual(left.filter { $0.kind == "gimbal_command" }.count,
                       left.filter { $0.kind == "gimbal_ack" }.count)
    }

    func testDropoutDisarmsAndDoesNotRearm() throws {
        let events = try ScenarioRunner.generate(ScenarioSettings(
            durationSeconds: 6, headDropoutStart: 2, headDropoutDuration: 2))
        XCTAssertEqual(SessionIntegrity.inspect(events).issueCount, 0)
        let disarms = events.filter { $0.kind == "disarm" }
        XCTAssertEqual(disarms.count, 1)
        let disarmTime = try XCTUnwrap(disarms.first?.uptime)
        XCTAssertFalse(events.contains { $0.kind == "gimbal_command" && $0.uptime > disarmTime })
    }

    func testRejectsAbsurdScenarioDurations() {
        XCTAssertThrowsError(try ScenarioRunner.generate(ScenarioSettings(durationSeconds: -1)))
    }
}
