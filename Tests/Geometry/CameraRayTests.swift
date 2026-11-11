import XCTest
@testable import AeroSpatialCore

final class CameraRayTests: XCTestCase {
    private let camera = CameraCalibration(fx: 1000, fy: 1000, cx: 960, cy: 540,
                                           width: 1920, height: 1080)
    func testOpticalRayAndGroundPlane() throws {
        let ray = try XCTUnwrap(CameraRay.direction(pixelX: 960, pixelY: 540,
                                                     calibration: camera))
        XCTAssertEqual(ray.z, 1, accuracy: 1e-12)
        let cameraPosition = SpatialVector(east: 0, north: 0, up: 100)
        let down = SpatialQuaternion(w: 0, x: 1, y: 0, z: 0)
        let target = try XCTUnwrap(CameraRay.intersectPlane(
            pixelX: 1460, pixelY: 540, calibration: camera, cameraPosition: cameraPosition,
            cameraToENU: down, planeUpMeters: 0, maximumRangeMeters: 2000))
        XCTAssertEqual(target.east, 50, accuracy: 1e-7)
        XCTAssertEqual(target.up, 0, accuracy: 1e-12)
        XCTAssertNil(CameraRay.intersectPlane(pixelX: 1460, pixelY: 540,
                                              calibration: camera, cameraPosition: cameraPosition,
                                              cameraToENU: down, planeUpMeters: 0,
                                              maximumRangeMeters: 100))
    }
    func testRejectsInvalidIntrinsicsAndUpwardRay() {
        XCTAssertNil(CameraRay.direction(pixelX: 1920, pixelY: 540, calibration: camera))
        let position = SpatialVector(east: 0, north: 0, up: 100)
        XCTAssertNil(CameraRay.intersectPlane(
            pixelX: 960, pixelY: 540, calibration: camera, cameraPosition: position,
            cameraToENU: SpatialQuaternion(w: 1, x: 0, y: 0, z: 0),
            planeUpMeters: 0, maximumRangeMeters: 2000))
    }
}
