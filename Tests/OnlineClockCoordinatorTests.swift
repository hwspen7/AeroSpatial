import XCTest
@testable import AeroSpatialCore

final class OnlineClockCoordinatorTests: XCTestCase {
    func testConvergesWithOffsetAndDrift() {
        var coordinator = OnlineClockCoordinator()
        for index in 0..<32 {
            let t = Double(index) * 0.03
            XCTAssertEqual(coordinator.observe(domain: 3, source: t,
                                                host: 100 + t * 1.00005), .accepted)
        }
        let mapped = coordinator.translate(domain: 3, source: 0.95,
                                           hostNow: 101.0, maximumError: 0.05)
        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped!.alignedSeconds, 100.9500475, accuracy: 0.005)
        XCTAssertNil(coordinator.translate(domain: 7, source: 0.9, hostNow: 101))
        XCTAssertNil(coordinator.translate(domain: 3, source: 0.9, hostNow: 105))
    }

    func testRejectsOutlierAndResetAfterLongGap() {
        var clock = OnlineClockCoordinator(maximumGapSeconds: 2)
        for i in 0..<16 {
            _ = clock.observe(domain: 4, source: Double(i) * 0.05,
                              host: 20 + Double(i) * 0.05)
        }
        XCTAssertEqual(clock.observe(domain: 4, source: 0.8, host: 22.0), .outlier)
        XCTAssertEqual(clock.observe(domain: 4, source: 0.8, host: 20.8), .accepted)
        XCTAssertEqual(clock.observe(domain: 4, source: 0.8, host: 20.8), .duplicateOrRegressed)
        XCTAssertEqual(clock.observe(domain: 4, source: 3.8, host: 23.8), .resetAfterGap)
        XCTAssertNil(clock.translate(domain: 4, source: 3.8, hostNow: 23.8))
    }

    func testMaxDomainsAndInvalidData() {
        var clock = OnlineClockCoordinator(maximumDomains: 1)
        XCTAssertEqual(clock.observe(domain: 0, source: 0, host: 0), .invalid)
        XCTAssertEqual(clock.observe(domain: 1, source: 0, host: 5), .accepted)
        XCTAssertEqual(clock.observe(domain: 2, source: 0, host: 5), .invalid)
        clock.reset(domain: 1)
        XCTAssertEqual(clock.observe(domain: 2, source: 0, host: 5), .accepted)
    }
}
