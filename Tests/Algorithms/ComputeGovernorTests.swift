import XCTest
@testable import AeroSpatialCore

final class ComputeGovernorTests: XCTestCase {
    func testRateAndPressureIsolation() throws {
        let governor = try XCTUnwrap(ComputeGovernor())
        XCTAssertTrue(governor.configure(stream: .perception, refillUnitsPerSecond: 10,
                                        burstUnits: 2, maximumPressurePermille: 700))
        XCTAssertEqual(governor.admit(stream: .perception, timestampNanoseconds: 0,
                                     estimatedUnits: 2, pressurePermille: 0), .admitted)
        XCTAssertEqual(governor.admit(stream: .perception, timestampNanoseconds: 0,
                                     estimatedUnits: 1, pressurePermille: 0), .rateLimited)
        XCTAssertEqual(governor.admit(stream: .perception, timestampNanoseconds: 100_000_000,
                                     estimatedUnits: 1, pressurePermille: 800), .backlogged)
        XCTAssertEqual(governor.admit(stream: .perception, timestampNanoseconds: 100_000_000,
                                     estimatedUnits: 1, pressurePermille: 0), .admitted)
        XCTAssertEqual(governor.admit(stream: .perception, timestampNanoseconds: 50_000_000,
                                     estimatedUnits: 1, pressurePermille: 0), .timeRegression)
        XCTAssertEqual(try XCTUnwrap(governor.stats(stream: .perception)).admitted, 2)
    }

    func testOnlyConfiguredStreamsAreAdmitted() throws {
        let governor = try XCTUnwrap(ComputeGovernor())
        XCTAssertEqual(governor.admit(stream: .video, timestampNanoseconds: 0,
                                     estimatedUnits: 1, pressurePermille: 0), .invalid)
        XCTAssertFalse(governor.configure(stream: .head, refillUnitsPerSecond: 10,
                                          burstUnits: 1, maximumPressurePermille: 100))
        XCTAssertFalse(governor.configure(stream: .video, refillUnitsPerSecond: 0,
                                          burstUnits: 1, maximumPressurePermille: 100))
    }
}
