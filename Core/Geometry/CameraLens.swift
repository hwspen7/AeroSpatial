import AeroSpatialNative
import Foundation

/// Brown-Conrady radial and tangential lens distortion coefficients.
public struct CameraLens: Equatable, Sendable {
    public let k1: Double
    public let k2: Double
    public let k3: Double
    public let p1: Double
    public let p2: Double

    public init(k1: Double, k2: Double, k3: Double = 0, p1: Double = 0, p2: Double = 0) {
        self.k1 = k1
        self.k2 = k2
        self.k3 = k3
        self.p1 = p1
        self.p2 = p2
    }
    var native: ASLensDistortion { ASLensDistortion(k1: k1, k2: k2, k3: k3, p1: p1, p2: p2) }
}

public enum CameraProjection {
    /// The direction is in the optical camera frame, not a world-coordinate bearing.
    public static func unproject(pixelX: Double, pixelY: Double,
                                 calibration: CameraCalibration, lens: CameraLens) -> ECEFVector? {
        var ray = ASVector3()
        guard as_camera_unproject_distorted(calibration.native, lens.native, pixelX, pixelY,
                                            &ray) == AS_OK else { return nil }
        return ECEFVector(x: ray.x, y: ray.y, z: ray.z)
    }

    public static func project(direction: ECEFVector,
                               calibration: CameraCalibration, lens: CameraLens) -> (Double, Double)? {
        var x = 0.0, y = 0.0
        let ray = ASVector3(x: direction.x, y: direction.y, z: direction.z)
        guard as_camera_project_distorted(calibration.native, lens.native, ray,
                                          &x, &y) == AS_OK else { return nil }
        return (x, y)
    }
}
