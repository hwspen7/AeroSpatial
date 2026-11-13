import XCTest
@testable import AeroSpatialCore

final class GeometryTests: XCTestCase {
    func testSignedAnglesAcrossWrapBoundary() {
        XCTAssertEqual(Angle.signedDegrees(190), -170, accuracy: 0.00001)
        XCTAssertEqual(Angle.signedDegrees(-190), 170, accuracy: 0.00001)
        XCTAssertEqual(Angle.signedDegrees(360), 0, accuracy: 0.00001)
        XCTAssertEqual(Angle.signedDegrees(-180), -180, accuracy: 0.00001)
    }

    func testCompassAngles() {
        XCTAssertEqual(Angle.compassDegrees(-45), 315)
        XCTAssertEqual(Angle.compassDegrees(405), 45)
    }

    func testInvalidPositionsRejected() {
        XCTAssertNil(Geodesy.relativePosition(from: .init(latitude: 120, longitude: 0),
                                              to: .init(latitude: 0, longitude: 0), observerHeadingDegrees: 0))
        XCTAssertNil(Geodesy.relativePosition(from: .init(latitude: 0, longitude: 0),
                                              to: .init(latitude: 0, longitude: 1), observerHeadingDegrees: .nan))
    }

    func testApproximateNorthAndEast() throws {
        let origin = GeoPoint(latitude: 0, longitude: 0)
        let east = try XCTUnwrap(Geodesy.relativePosition(from: origin,
                                                          to: .init(latitude: 0, longitude: 0.001),
                                                          observerHeadingDegrees: 0))
        XCTAssertEqual(east.bearingDegrees, 90, accuracy: 0.001)
        XCTAssertEqual(east.relativeBearingDegrees, 90, accuracy: 0.001)
        XCTAssertEqual(east.distanceMeters, 111.195, accuracy: 0.2)
        let north = try XCTUnwrap(Geodesy.relativePosition(from: origin,
                                                           to: .init(latitude: 0.001, longitude: 0),
                                                           observerHeadingDegrees: 90))
        XCTAssertEqual(north.bearingDegrees, 0, accuracy: 0.001)
        XCTAssertEqual(north.relativeBearingDegrees, -90, accuracy: 0.001)
    }

    func testDirectionsAndStereoPan() {
        XCTAssertEqual(DirectionCue.label(relativeBearing: 0), "Ahead")
        XCTAssertEqual(DirectionCue.label(relativeBearing: 90), "Right")
        XCTAssertEqual(DirectionCue.label(relativeBearing: -90), "Left")
        XCTAssertEqual(DirectionCue.label(relativeBearing: 179), "Behind")
        XCTAssertEqual(DirectionCue.stereoPan(relativeBearing: 90), 1, accuracy: 0.00001)
        XCTAssertEqual(DirectionCue.stereoPan(relativeBearing: -90), -1, accuracy: 0.00001)
    }
}
