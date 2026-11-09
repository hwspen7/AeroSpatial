import XCTest
@testable import AeroSpatialCore

final class NativeFramesTests: XCTestCase {
    func testWGS84CoordinateAndDateline() throws {
        let a = GeodeticPosition(latitude: 0, longitude: 0, ellipsoidHeightMeters: 0)
        let b = GeodeticPosition(latitude: 0, longitude: 0, ellipsoidHeightMeters: 25)
        XCTAssertEqual(try XCTUnwrap(NativeFrames.ecef(a)).x, 6378137, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(NativeFrames.enu(from: a, to: b)).up, 25, accuracy: 1e-6)
        let east = try XCTUnwrap(NativeFrames.enu(
            from: .init(latitude: 0, longitude: 179.999, ellipsoidHeightMeters: 0),
            to: .init(latitude: 0, longitude: -179.999, ellipsoidHeightMeters: 0)))
        XCTAssertTrue((220...225).contains(east.east))
        XCTAssertNil(NativeFrames.ecef(.init(latitude: 95, longitude: 0, ellipsoidHeightMeters: 0)))
    }

    func testSlerpUsesShortestArc() throws {
        let start = try XCTUnwrap(NativeGeometry.quaternion(yaw: 0, pitch: 0, roll: 0))
        let end = try XCTUnwrap(NativeGeometry.quaternion(yaw: 90, pitch: 0, roll: 0))
        let middle = try XCTUnwrap(NativeFrames.interpolate(start, end, fraction: 0.5))
        let rotated = try XCTUnwrap(NativeGeometry.rotate(
            SpatialVector(east: 1, north: 0, up: 0), by: middle))
        XCTAssertEqual(rotated.east, 0.70710678, accuracy: 1e-6)
        XCTAssertEqual(rotated.north, 0.70710678, accuracy: 1e-6)
        XCTAssertNil(NativeFrames.interpolate(start, end, fraction: 1.5))
    }
}
