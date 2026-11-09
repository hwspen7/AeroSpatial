import XCTest
@testable import AeroSpatialCore

final class NativeIntegrationTests: XCTestCase {
    func testGeodesyDatelineAndLocalFrame() throws {
        let origin = GeoPoint(latitude: 0, longitude: 179.999)
        let target = GeoPoint(latitude: 0, longitude: -179.999)
        let result = try XCTUnwrap(NativeGeometry.geodesic(from: origin, to: target))
        XCTAssertEqual(result.distanceMeters, 222.39, accuracy: 1)
        let enu = try XCTUnwrap(NativeGeometry.localENU(from: origin, to: target,
                                                       elevationDifferenceMeters: 5))
        XCTAssertEqual(enu.east, 222.39, accuracy: 1)
        XCTAssertEqual(enu.up, 5)
        XCTAssertNil(NativeGeometry.localENU(from: origin,
                      to: GeoPoint(latitude: 60, longitude: 60), elevationDifferenceMeters: 0))
    }

    func testQuaternionRotate() throws {
        let quaternion = try XCTUnwrap(NativeGeometry.quaternion(yaw: 90, pitch: 0, roll: 0))
        let rotated = try XCTUnwrap(NativeGeometry.rotate(
            SpatialVector(east: 1, north: 0, up: 0), by: quaternion))
        XCTAssertEqual(rotated.east, 0, accuracy: 1e-8)
        XCTAssertEqual(rotated.north, 1, accuracy: 1e-8)
        XCTAssertNil(NativeGeometry.quaternion(yaw: .nan, pitch: 0, roll: 0))
    }

    func testPredictorOutliersAndTimeGaps() {
        var filter = NativeSignalFilter()
        XCTAssertEqual(filter.observe(value: 4, at: 1), .accepted(4))
        XCTAssertEqual(filter.observe(value: 6, at: 1.1), .accepted(5))
        XCTAssertEqual(filter.observe(value: 99, at: 1.2), .outlier)
        XCTAssertEqual(filter.observe(value: 0, at: 1.05), .outOfOrder)
        XCTAssertEqual(filter.observe(value: 7, at: 3), .resetAfterGap(7))
        filter.reset()
        XCTAssertNil(filter.position)
    }

    func testPanIsClearlyStereoOnly() throws {
        XCTAssertEqual(try XCTUnwrap(NativeGeometry.pan(relativeBearingDegrees: 90)), 1, accuracy: 1e-10)
        XCTAssertEqual(DirectionCue.stereoPan(relativeBearing: -90), -1, accuracy: 1e-10)
    }
}
