import XCTest
@testable import AeroSpatialCore

final class ClockUncertaintyTests: XCTestCase {
    func testExplicitErrorPropagation() {
        var bridge = ClockBridge()
        XCTAssertNil(bridge.estimate(remote: 2, referenceRemote: 1,
                                     calibrationErrorSeconds: 0.001))
        XCTAssertEqual(bridge.observe(remote: 100, local: 110), .accepted)
        let estimate = bridge.estimate(remote: 110, referenceRemote: 100,
                                       calibrationErrorSeconds: 0.002, driftPPM: 100)
        XCTAssertEqual(estimate?.alignedSeconds, 120)
        XCTAssertEqual(estimate?.maximumErrorSeconds ?? -1, 0.003, accuracy: 1e-10)
        XCTAssertNil(bridge.estimate(remote: .nan, referenceRemote: 100,
                                      calibrationErrorSeconds: 0.002))
    }
}
