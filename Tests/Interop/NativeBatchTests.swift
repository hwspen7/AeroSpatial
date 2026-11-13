import XCTest
@testable import AeroSpatialCore

final class NativeBatchTests: XCTestCase {
    func testBatchMatchesScalarGeodesy() throws {
        let samples = (0..<200).map { index in
            GeodeticPosition(latitude: 40 + Double(index) / 10000, longitude: -83,
                             ellipsoidHeightMeters: 200)
        }
        let result = try NativeBatch.ecef(points: samples)
        XCTAssertEqual(result.count, samples.count)
        for index in 0..<samples.count {
            let scalar = try XCTUnwrap(NativeFrames.ecef(samples[index]))
            XCTAssertEqual(result[index].x, scalar.x, accuracy: 1e-7)
            XCTAssertEqual(result[index].y, scalar.y, accuracy: 1e-7)
            XCTAssertEqual(result[index].z, scalar.z, accuracy: 1e-7)
        }
    }

    func testFilterBatchInPlaceSemanticsAndRejection() throws {
        let values = try NativeBatch.lowpass([10, 12, 14], alpha: 0.5)
        XCTAssertEqual(values[0], 5, accuracy: 1e-12)
        XCTAssertEqual(values[1], 8.5, accuracy: 1e-12)
        XCTAssertThrowsError(try NativeBatch.lowpass([10, .nan], alpha: 0.5))
        XCTAssertThrowsError(try NativeBatch.ecef(points: [
            GeodeticPosition(latitude: 92, longitude: 0, ellipsoidHeightMeters: 0)]))
    }
}
