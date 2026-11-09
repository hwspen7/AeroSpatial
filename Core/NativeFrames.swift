import Foundation
import AeroSpatialNative

/// WGS84 position with ellipsoidal height, not a DJI relative flight altitude.
public struct GeodeticPosition: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let ellipsoidHeightMeters: Double

    public init(latitude: Double, longitude: Double, ellipsoidHeightMeters: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.ellipsoidHeightMeters = ellipsoidHeightMeters
    }

    fileprivate var native: ASGeodetic3 {
        ASGeodetic3(latitude: latitude, longitude: longitude, altitude: ellipsoidHeightMeters)
    }
}

/// Geocentric Earth-fixed position in meters, distinct from a local ENU vector.
public struct ECEFVector: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double
}

public enum NativeFrames {
    public static func ecef(_ point: GeodeticPosition) -> ECEFVector? {
        var result = ASVector3(x: 0, y: 0, z: 0)
        guard as_wgs84_ecef(point.native, &result) == AS_OK else { return nil }
        return ECEFVector(x: result.x, y: result.y, z: result.z)
    }

    public static func enu(from origin: GeodeticPosition,
                           to target: GeodeticPosition) -> SpatialVector? {
        var result = ASVector3(x: 0, y: 0, z: 0)
        guard as_wgs84_enu(origin.native, target.native, &result) == AS_OK else { return nil }
        return SpatialVector(east: result.x, north: result.y, up: result.z)
    }

    public static func interpolate(_ from: SpatialQuaternion, _ to: SpatialQuaternion,
                                   fraction: Double) -> SpatialQuaternion? {
        var result = ASQuaternion(w: 1, x: 0, y: 0, z: 0)
        let a = ASQuaternion(w: from.w, x: from.x, y: from.y, z: from.z)
        let b = ASQuaternion(w: to.w, x: to.x, y: to.y, z: to.z)
        guard as_quaternion_slerp(a, b, fraction, &result) == AS_OK else { return nil }
        return SpatialQuaternion(w: result.w, x: result.x, y: result.y, z: result.z)
    }
}
