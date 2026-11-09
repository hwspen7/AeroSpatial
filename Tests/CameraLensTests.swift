import XCTest
@testable import AeroSpatialCore

final class CameraLensTests: XCTestCase {
    func testDistortedProjectionRoundTrip() throws {
        let camera = CameraCalibration(fx: 1000, fy: 990, cx: 640, cy: 360, width: 1280, height: 720)
        let lens = CameraLens(k1: -0.14, k2: 0.03, p1: 0.002, p2: -0.001)
        for x in stride(from: 40.0, to: 1250.0, by: 170) {
            for y in stride(from: 50.0, to: 690.0, by: 110) {
                let direction = try XCTUnwrap(CameraProjection.unproject(pixelX: x, pixelY: y,
                                                                         calibration: camera, lens: lens))
                let pixel = try XCTUnwrap(CameraProjection.project(direction: direction,
                                                                   calibration: camera, lens: lens))
                XCTAssertEqual(pixel.0, x, accuracy: 1e-6)
                XCTAssertEqual(pixel.1, y, accuracy: 1e-6)
            }
        }
        XCTAssertNil(CameraProjection.unproject(pixelX: -1, pixelY: 50, calibration: camera, lens: lens))
    }
}
