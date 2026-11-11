import XCTest
@testable import AeroSpatialCore

final class TimedFrameGraphTests: XCTestCase {
    func testExplicitClockAndExpiryGates() throws {
        let body = try XCTUnwrap(FrameIdentifier("drone_body"))
        let camera = try XCTUnwrap(FrameIdentifier("camera_optical"))
        let fixed = SpatialTransform(translation: SpatialVector(east: 1, north: 0, up: 0),
                                     rotation: SpatialQuaternion(w: 1, x: 0, y: 0, z: 0))
        let a = try XCTUnwrap(TimedFrameCalibration(identifier: "calibration_001",
            parent: body, child: camera, transform: fixed,
            validFromNanoseconds: 100, validUntilNanoseconds: 1000, clockDomain: 7))
        var graph = TimedFrameGraph()
        XCTAssertTrue(graph.add(a))
        XCTAssertFalse(graph.add(a))
        XCTAssertNotNil(graph.resolve(from: camera, to: body, at: 500,
                                      uncertaintyNanoseconds: 10, clockDomain: 7))
        XCTAssertNil(graph.resolve(from: camera, to: body, at: 500,
                                   uncertaintyNanoseconds: 10, clockDomain: 8))
        XCTAssertNil(graph.resolve(from: camera, to: body, at: 990,
                                   uncertaintyNanoseconds: 20, clockDomain: 7))
        let b = try XCTUnwrap(TimedFrameCalibration(identifier: "calibration_002",
            parent: body, child: camera, transform: fixed,
            validFromNanoseconds: 1000, validUntilNanoseconds: 2000, clockDomain: 7))
        XCTAssertTrue(graph.add(b))
        XCTAssertNotNil(graph.resolve(from: camera, to: body, at: 1200,
                                      uncertaintyNanoseconds: 20, clockDomain: 7))
        XCTAssertNil(TimedFrameCalibration(identifier: "bad", parent: body,
            child: camera, transform: fixed,
            validFromNanoseconds: 1000, validUntilNanoseconds: 1000, clockDomain: 7))
    }
}
