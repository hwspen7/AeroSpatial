import XCTest
@testable import AeroSpatialCore

final class FrameGraphTests: XCTestCase {
    func testTransformCompositionAndInverse() throws {
        let yaw = try XCTUnwrap(NativeGeometry.quaternion(yaw: 90, pitch: 0, roll: 0))
        let mapping = SpatialTransform(translation: SpatialVector(east: 10, north: 5, up: 3),
                                       rotation: yaw)
        let point = SpatialVector(east: 2, north: 0, up: 0)
        let result = try XCTUnwrap(mapping.applying(to: point))
        XCTAssertEqual(result.east, 10, accuracy: 1e-8)
        XCTAssertEqual(result.north, 7, accuracy: 1e-8)
        let back = try XCTUnwrap(mapping.inverted()?.applying(to: result))
        XCTAssertEqual(back.east, point.east, accuracy: 1e-8)
        XCTAssertEqual(back.north, point.north, accuracy: 1e-8)
    }

    func testGraphPathsAndNoInventedFrames() throws {
        let world = try XCTUnwrap(FrameIdentifier("world"))
        let drone = try XCTUnwrap(FrameIdentifier("aircraft"))
        let camera = try XCTUnwrap(FrameIdentifier("camera"))
        let orphan = try XCTUnwrap(FrameIdentifier("unobserved"))
        let yaw = try XCTUnwrap(NativeGeometry.quaternion(yaw: 90, pitch: 0, roll: 0))
        var graph = FrameGraph()
        XCTAssertTrue(graph.link(parent: world, child: drone,
                                 transform: SpatialTransform(translation: SpatialVector(
                                    east: 10, north: 0, up: 0), rotation: yaw)))
        XCTAssertTrue(graph.link(parent: drone, child: camera,
                                 transform: SpatialTransform(translation: SpatialVector(
                                    east: 1, north: 0, up: 0), rotation: SpatialTransform.identity.rotation)))
        let result = try XCTUnwrap(graph.resolve(from: camera, to: world)?.applying(
            to: SpatialVector(east: 0, north: 0, up: 0)))
        XCTAssertEqual(result.east, 10, accuracy: 1e-8)
        XCTAssertEqual(result.north, 1, accuracy: 1e-8)
        XCTAssertNil(graph.resolve(from: orphan, to: world))
        XCTAssertFalse(graph.link(parent: world, child: camera, transform: .identity))
        graph.remove(parent: drone, child: camera)
        XCTAssertNil(graph.resolve(from: camera, to: world))
    }

    func testInvalidFrameId() {
        XCTAssertNil(FrameIdentifier("gps/../../secret"))
        XCTAssertNil(FrameIdentifier(""))
    }
}
