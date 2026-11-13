import XCTest
@testable import AeroSpatialCore

final class PlanarTrackerTests: XCTestCase {
    func testPositionVelocityFusionAndInnovationGate() {
        var tracker = PlanarTracker()
        for i in 0..<100 {
            let t = Double(i) * 0.1
            XCTAssertEqual(tracker.observe(PlanarObservation(eastMeters: 2 * t,
                                                               northMeters: -0.8 * t,
                                                               seconds: t),
                                           measurementStdMeters: 0.2), .accepted)
        }
        XCTAssertTrue(tracker.isInitialized)
        XCTAssertEqual(tracker.eastVelocity, 2, accuracy: 0.1)
        XCTAssertEqual(tracker.northVelocity, -0.8, accuracy: 0.1)
        let previous = tracker.eastMeters
        XCTAssertEqual(tracker.observe(PlanarObservation(eastMeters: 10000,
                                                          northMeters: 10000, seconds: 10),
                                       measurementStdMeters: 0.2), .rejectedOutlier)
        XCTAssertLessThan(tracker.eastMeters, previous + 1)
        XCTAssertEqual(tracker.observe(PlanarObservation(eastMeters: 3,
                                                          northMeters: 3, seconds: 40),
                                       measurementStdMeters: 0.2), .resetAfterGap)
    }
}
