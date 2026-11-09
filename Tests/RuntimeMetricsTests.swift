import XCTest
@testable import AeroSpatialCore

final class RuntimeMetricsTests: XCTestCase {
    func testPercentilesAndInvalidValues() {
        var metrics = RuntimeMetrics()
        XCTAssertNil(metrics.upperBoundMicroseconds(percentile: 0.95))
        for _ in 0..<99 { metrics.observe(durationSeconds: 0.001) }
        metrics.observe(durationSeconds: 0.15, accepted: false)
        metrics.observe(durationSeconds: -.infinity)
        XCTAssertEqual(metrics.samples, 100)
        XCTAssertEqual(metrics.rejected, 1)
        XCTAssertEqual(metrics.invalid, 1)
        XCTAssertEqual(metrics.maxDurationMicroseconds, 150000)
        XCTAssertFalse(metrics.exceedsLatencyBudget(10000))
        XCTAssertTrue(metrics.exceedsLatencyBudget(10))
    }
}
