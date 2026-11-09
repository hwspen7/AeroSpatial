import XCTest
@testable import AeroSpatialCore

final class RobustClockTests: XCTestCase {
    func testEstimateWithOutlierAndBoundedExtrapolation() throws {
        var pairs = (0..<32).map { index in
            let source = 10000 + Double(index) * 0.5
            return ClockPair(sourceSeconds: source,
                             hostSeconds: 50 + source * 1.00008 + (index.isMultiple(of: 2) ? 0.0001 : -0.0001))
        }
        pairs[7] = ClockPair(sourceSeconds: pairs[7].sourceSeconds,
                             hostSeconds: pairs[7].hostSeconds + 0.15)
        let result = try XCTUnwrap(RobustClock.fit(pairs))
        XCTAssertEqual(result.rejected, 1)
        XCTAssertLessThan(abs(result.scale - 1.00008), 1e-5)
        let prediction = try XCTUnwrap(result.translate(sourceSeconds: 10005))
        XCTAssertLessThan(abs(prediction.hostSeconds - (50 + 10005 * 1.00008)), 0.003)
        XCTAssertNil(result.translate(sourceSeconds: 10100))
        XCTAssertNotNil(result.translate(sourceSeconds: 10016, maximumExtrapolationSeconds: 1))
    }

    func testInvalidClockIsRejected() {
        XCTAssertNil(RobustClock.fit([ClockPair(sourceSeconds: 1, hostSeconds: 1)]))
        XCTAssertNil(RobustClock.fit((0..<8).map {
            ClockPair(sourceSeconds: Double($0), hostSeconds: Double($0) * 1.5)
        }))
    }
}
