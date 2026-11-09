import Foundation
import AeroSpatialNative

public struct SpatialVector: Equatable, Sendable {
    public var east: Double
    public var north: Double
    public var up: Double

    public init(east: Double, north: Double, up: Double) {
        self.east = east
        self.north = north
        self.up = up
    }
}

public struct SpatialQuaternion: Equatable, Sendable {
    public var w: Double
    public var x: Double
    public var y: Double
    public var z: Double
}

/// Thin, checked Swift interface to the portable C++ geometry kernel.
public enum NativeGeometry {
    public static func geodesic(from origin: GeoPoint, to target: GeoPoint)
        -> (distanceMeters: Double, bearingDegrees: Double)? {
        var distance = 0.0
        var bearing = 0.0
        let status = as_geodesic(
            ASGeodetic(latitude: origin.latitude, longitude: origin.longitude),
            ASGeodetic(latitude: target.latitude, longitude: target.longitude),
            &distance, &bearing)
        guard status == AS_OK else { return nil }
        return (distance, bearing)
    }

    /// A local 3D offset, only valid within 50 km of the origin.
    /// Both altitudes must use the same vertical datum.
    public static func localENU(from origin: GeoPoint, to target: GeoPoint,
                                elevationDifferenceMeters: Double) -> SpatialVector? {
        var vector = ASVector3(x: 0, y: 0, z: 0)
        let status = as_local_enu(
            ASGeodetic(latitude: origin.latitude, longitude: origin.longitude),
            ASGeodetic(latitude: target.latitude, longitude: target.longitude),
            elevationDifferenceMeters, &vector)
        guard status == AS_OK else { return nil }
        return SpatialVector(east: vector.x, north: vector.y, up: vector.z)
    }

    /// ENU right-handed frame: yaw about up, pitch about north, roll about east.
    public static func quaternion(yaw: Double, pitch: Double, roll: Double)
        -> SpatialQuaternion? {
        var value = ASQuaternion(w: 1, x: 0, y: 0, z: 0)
        guard as_euler_to_quaternion(yaw, pitch, roll, &value) == AS_OK else { return nil }
        return SpatialQuaternion(w: value.w, x: value.x, y: value.y, z: value.z)
    }

    public static func rotate(_ input: SpatialVector, by rotation: SpatialQuaternion)
        -> SpatialVector? {
        var result = ASVector3(x: 0, y: 0, z: 0)
        let status = as_rotate_vector(
            ASQuaternion(w: rotation.w, x: rotation.x, y: rotation.y, z: rotation.z),
            ASVector3(x: input.east, y: input.north, z: input.up), &result)
        guard status == AS_OK else { return nil }
        return SpatialVector(east: result.x, north: result.y, up: result.z)
    }

    public static func pan(relativeBearingDegrees: Double) -> Double? {
        var result = 0.0
        guard as_stereo_pan(relativeBearingDegrees, &result) == AS_OK else { return nil }
        return result
    }
}
