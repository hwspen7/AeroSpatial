import AeroSpatialNative
import Foundation

/// Camera-space direction and optional ENU reference-plane intersection.
/// Requires real camera calibration, extrinsics and a consistent vertical datum.
public struct CameraCalibration: Equatable, Sendable {
    public let fx: Double
    public let fy: Double
    public let cx: Double
    public let cy: Double
    public let width: UInt32
    public let height: UInt32

    public init(fx: Double, fy: Double, cx: Double, cy: Double,
                width: UInt32, height: UInt32) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.width = width
        self.height = height
    }

    var native: ASCameraIntrinsics {
        ASCameraIntrinsics(fx: fx, fy: fy, cx: cx, cy: cy, width: width, height: height)
    }
}

public enum CameraRay {
    /// Camera optical frame: X right, Y down, Z forward.
    public static func direction(pixelX: Double, pixelY: Double,
                                 calibration: CameraCalibration) -> ECEFVector? {
        var ray = ASVector3()
        guard as_camera_unproject(calibration.native, pixelX, pixelY, &ray) == AS_OK else {
            return nil
        }
        return ECEFVector(x: ray.x, y: ray.y, z: ray.z)
    }

    /// Not terrain geolocation or a target coordinate without a verified plane.
    public static func intersectPlane(pixelX: Double, pixelY: Double,
                                      calibration: CameraCalibration,
                                      cameraPosition: SpatialVector,
                                      cameraToENU: SpatialQuaternion,
                                      planeUpMeters: Double, maximumRangeMeters: Double)
        -> SpatialVector? {
        var location = ASVector3()
        let position = ASVector3(x: cameraPosition.east, y: cameraPosition.north,
                                 z: cameraPosition.up)
        let rotation = ASQuaternion(w: cameraToENU.w, x: cameraToENU.x,
                                    y: cameraToENU.y, z: cameraToENU.z)
        let status = as_camera_ground_intersection(calibration.native, pixelX, pixelY,
                                                    position, rotation, planeUpMeters,
                                                    maximumRangeMeters, &location)
        guard status == AS_OK else { return nil }
        return SpatialVector(east: location.x, north: location.y, up: location.z)
    }
}
