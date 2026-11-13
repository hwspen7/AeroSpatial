import Foundation
import AeroSpatialNative

/// Rigid transform from child coordinates to parent coordinates, in meters.
public struct SpatialTransform: Equatable, Sendable {
    public let translation: SpatialVector
    public let rotation: SpatialQuaternion

    public init(translation: SpatialVector, rotation: SpatialQuaternion) {
        self.translation = translation
        self.rotation = rotation
    }

    public static let identity = SpatialTransform(
        translation: SpatialVector(east: 0, north: 0, up: 0),
        rotation: SpatialQuaternion(w: 1, x: 0, y: 0, z: 0))

    public func applying(to point: SpatialVector) -> SpatialVector? {
        guard let rotated = NativeGeometry.rotate(point, by: rotation) else { return nil }
        return SpatialVector(east: translation.east + rotated.east,
                             north: translation.north + rotated.north,
                             up: translation.up + rotated.up)
    }

    /// self maps B -> A, child maps C -> B; returned transform maps C -> A.
    public func composed(with child: SpatialTransform) -> SpatialTransform? {
        guard let shifted = applying(to: child.translation),
              let combined = Self.product(rotation, child.rotation) else { return nil }
        return SpatialTransform(translation: shifted, rotation: combined)
    }

    public func inverted() -> SpatialTransform? {
        var inverse = ASQuaternion(w: 1, x: 0, y: 0, z: 0)
        guard as_quaternion_inverse(rotation.native, &inverse) == AS_OK else { return nil }
        let invRotation = SpatialQuaternion(w: inverse.w, x: inverse.x, y: inverse.y, z: inverse.z)
        guard let shift = NativeGeometry.rotate(
            SpatialVector(east: -translation.east, north: -translation.north,
                          up: -translation.up), by: invRotation) else { return nil }
        return SpatialTransform(translation: shift, rotation: invRotation)
    }

    private static func product(_ a: SpatialQuaternion, _ b: SpatialQuaternion) -> SpatialQuaternion? {
        var result = ASQuaternion(w: 1, x: 0, y: 0, z: 0)
        guard as_quaternion_multiply(a.native, b.native, &result) == AS_OK else { return nil }
        return SpatialQuaternion(w: result.w, x: result.x, y: result.y, z: result.z)
    }
}

private extension SpatialQuaternion {
    var native: ASQuaternion { ASQuaternion(w: w, x: x, y: y, z: z) }
}
