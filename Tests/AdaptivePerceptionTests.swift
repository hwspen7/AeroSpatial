import XCTest
@testable import AeroSpatialCore

final class AdaptivePerceptionTests: XCTestCase {
    func testOverloadAndRecovery() {
        var governor = AdaptivePerception()
        XCTAssertEqual(governor.update(timestampNanoseconds: 1_000_000_000,
                       pressurePermille: 50, thermalLevel: 0, latencyMilliseconds: 2,
                       budgetMilliseconds: 10), .full)
        XCTAssertEqual(governor.update(timestampNanoseconds: 1_100_000_000,
                       pressurePermille: 950, thermalLevel: 3, latencyMilliseconds: 30,
                       budgetMilliseconds: 10), .reduced)
        XCTAssertNil(governor.update(timestampNanoseconds: 1_100_000_000,
                       pressurePermille: 0, thermalLevel: 0, latencyMilliseconds: 1,
                       budgetMilliseconds: 10))
        for i in 0..<10 {
            _ = governor.update(timestampNanoseconds: UInt64(1_500_000_000 + i * 300_000_000),
                       pressurePermille: 100, thermalLevel: 0, latencyMilliseconds: 1,
                       budgetMilliseconds: 10)
        }
        XCTAssertEqual(governor.update(timestampNanoseconds: 6_000_000_000,
                       pressurePermille: 100, thermalLevel: 0, latencyMilliseconds: 1,
                       budgetMilliseconds: 10), .full)
    }

    func testHeadPredictionDoesNotAuthorizeMotion() {
        var predictor = HeadIntentPredictor()
        XCTAssertEqual(predictor.observe(seconds: 1, yawDegrees: 179,
                                         pitchDegrees: 0)?.yawDegrees, 179)
        let result = predictor.observe(seconds: 1.1, yawDegrees: -179, pitchDegrees: 1)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.yawRateDegreesPerSecond, 0)
        XCTAssertNil(predictor.observe(seconds: 1.1, yawDegrees: 0, pitchDegrees: 1))
        XCTAssertNil(predictor.observe(seconds: 1.101, yawDegrees: 120, pitchDegrees: 1))
    }
}
