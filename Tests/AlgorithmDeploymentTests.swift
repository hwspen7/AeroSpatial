import XCTest
@testable import AeroSpatialCore

final class AlgorithmDeploymentTests: XCTestCase {
    private func algorithm(inputs: [SpatialStream], hardware: Bool = false) -> AlgorithmManifest {
        AlgorithmManifest(identifier: "camera_detection", inputs: inputs, outputs: [.perception],
                          dependencies: [], memoryBudgetBytes: 1024, deadlineMilliseconds: 100,
                          deterministic: false, requiresHardware: hardware)
    }

    func testUnverifiedDJIDoesNotImplicitlyGrantHardware() {
        XCTAssertEqual(AlgorithmDeployment.evaluate(algorithm(inputs: [.video], hardware: true),
                                                     device: .unverifiedDJI,
                                                     hasHeadMotion: true, hardwareVerified: false),
                       .unverifiedHardware)
        XCTAssertEqual(AlgorithmDeployment.evaluate(algorithm(inputs: [.video]),
                                                     device: .unverifiedDJI,
                                                     hasHeadMotion: true, hardwareVerified: false),
                       .missingVideo)
    }

    func testInputCapabilitiesMustBeExplicitlyAvailable() {
        XCTAssertEqual(AlgorithmDeployment.evaluate(algorithm(inputs: [.head]),
                                                     device: .simulator,
                                                     hasHeadMotion: false, hardwareVerified: false),
                       .missingHeadSensor)
        XCTAssertEqual(AlgorithmDeployment.evaluate(algorithm(inputs: [.telemetry]),
                                                     device: .simulator,
                                                     hasHeadMotion: true, hardwareVerified: false),
                       .supported)
    }
}
