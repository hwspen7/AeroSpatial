import XCTest
@testable import AeroSpatialCore

final class AlgorithmRegistryTests: XCTestCase {
    private func manifest(_ id: String, dependencies: [String] = [],
                          outputs: [SpatialStream] = [.perception],
                          inputs: [SpatialStream] = [.video]) -> AlgorithmManifest {
        AlgorithmManifest(identifier: id, inputs: inputs, outputs: outputs,
                          dependencies: dependencies, memoryBudgetBytes: 4096,
                          deadlineMilliseconds: 100, deterministic: true, requiresHardware: false)
    }

    func testStableDependencyOrderIndependentOfRegistration() throws {
        var registry = AlgorithmRegistry()
        try registry.register(manifest("final_analysis", dependencies: ["input_analysis"],
                                       outputs: [.diagnostic], inputs: [.perception]))
        try registry.register(manifest("input_analysis"))
        XCTAssertEqual(try registry.executionPlan().map(\.identifier),
                       ["input_analysis", "final_analysis"])
        XCTAssertThrowsError(try registry.register(manifest("input_analysis")))
    }

    func testCycleMissingAndUnsafeOutputsRejected() throws {
        var missing = AlgorithmRegistry()
        try missing.register(manifest("final_analysis", dependencies: ["unknown"] ))
        XCTAssertThrowsError(try missing.executionPlan())
        var cycle = AlgorithmRegistry()
        try cycle.register(manifest("first_step", dependencies: ["second_step"]))
        try cycle.register(manifest("second_step", dependencies: ["first_step"]))
        XCTAssertThrowsError(try cycle.executionPlan())
        var rejected = AlgorithmRegistry()
        XCTAssertThrowsError(try rejected.register(manifest("spoof_head", outputs: [.head])))
        XCTAssertThrowsError(try rejected.register(manifest("spoof_flight", outputs: [.telemetry])))
    }

    func testFixtureRoundTrip() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/algorithms.json")
        let data = try Data(contentsOf: url)
        let manifests = try JSONDecoder().decode([AlgorithmManifest].self, from: data)
        var registry = AlgorithmRegistry()
        for item in manifests.reversed() { try registry.register(item) }
        XCTAssertEqual(try registry.executionPlan().map(\.identifier),
                       ["object_detector", "place_indexer"])
        let json = try JSONEncoder().encode(manifests)
        XCTAssertEqual(try JSONDecoder().decode([AlgorithmManifest].self, from: json), manifests)
    }
}
