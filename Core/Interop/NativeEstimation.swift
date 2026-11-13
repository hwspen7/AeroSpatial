import AeroSpatialNative
import Foundation

/// Device-neutral SE(3) pose, mapping body coordinates into local ENU.
public struct SpatialPose3: Equatable, Sendable {
    public var position: SpatialVector
    public var orientation: SpatialQuaternion

    public init(position: SpatialVector, orientation: SpatialQuaternion) {
        self.position = position
        self.orientation = orientation
    }

    fileprivate var native: ASPose3 {
        ASPose3(translation_m: ASVector3(x: position.east, y: position.north, z: position.up),
                rotation: ASQuaternion(w: orientation.w, x: orientation.x,
                                       y: orientation.y, z: orientation.z))
    }

    fileprivate init(native: ASPose3) {
        position = SpatialVector(east: native.translation_m.x,
                                 north: native.translation_m.y, up: native.translation_m.z)
        orientation = SpatialQuaternion(w: native.rotation.w, x: native.rotation.x,
                                         y: native.rotation.y, z: native.rotation.z)
    }
}

public enum NativePoseMath {
    /// Twist ordering: translation in meters followed by rotation vector in radians.
    public static func exponential(_ twist: [Double]) -> SpatialPose3? {
        guard twist.count == 6 else { return nil }
        var result = ASPose3()
        let status = twist.withUnsafeBufferPointer { as_pose_exp($0.baseAddress, &result) }
        return status == AS_OK ? SpatialPose3(native: result) : nil
    }

    public static func logarithm(_ pose: SpatialPose3) -> [Double]? {
        var twist = [Double](repeating: 0, count: 6)
        let status = twist.withUnsafeMutableBufferPointer {
            as_pose_log(pose.native, $0.baseAddress)
        }
        return status == AS_OK ? twist : nil
    }

    public static func composed(_ a: SpatialPose3, with b: SpatialPose3) -> SpatialPose3? {
        var result = ASPose3()
        return as_pose_compose(a.native, b.native, &result) == AS_OK
            ? SpatialPose3(native: result) : nil
    }

    public static func inverse(_ pose: SpatialPose3) -> SpatialPose3? {
        var result = ASPose3()
        return as_pose_inverse(pose.native, &result) == AS_OK
            ? SpatialPose3(native: result) : nil
    }

    /// Row-major independent left-perturbation covariance matrices.
    public static func composedCovariance(_ a: SpatialPose3,
                                          first: [Double], second: [Double]) -> [Double]? {
        guard first.count == 36, second.count == 36 else { return nil }
        var result = [Double](repeating: 0, count: 36)
        let status = first.withUnsafeBufferPointer { pa in
            second.withUnsafeBufferPointer { pb in
                result.withUnsafeMutableBufferPointer { output in
                    as_pose_covariance_compose(a.native, pa.baseAddress, pb.baseAddress,
                                               output.baseAddress)
                }
            }
        }
        return status == AS_OK ? result : nil
    }
}

public struct InertialNoise: Sendable {
    public let accelerometerStd: Double
    public let gyroscopeStd: Double
    public let accelerometerBiasWalk: Double
    public let gyroscopeBiasWalk: Double
    public let maximumStepSeconds: Double

    public init(accelerometerStd: Double, gyroscopeStd: Double,
                accelerometerBiasWalk: Double, gyroscopeBiasWalk: Double,
                maximumStepSeconds: Double = 0.1) {
        self.accelerometerStd = accelerometerStd
        self.gyroscopeStd = gyroscopeStd
        self.accelerometerBiasWalk = accelerometerBiasWalk
        self.gyroscopeBiasWalk = gyroscopeBiasWalk
        self.maximumStepSeconds = maximumStepSeconds
    }

    fileprivate var native: ASInertialNoise {
        ASInertialNoise(accelerometer_std_mps2: accelerometerStd,
                        gyroscope_std_rps: gyroscopeStd,
                        accelerometer_bias_walk_mps2: accelerometerBiasWalk,
                        gyroscope_bias_walk_rps: gyroscopeBiasWalk,
                        maximum_step_s: maximumStepSeconds)
    }
}

/// 15-error-state inertial predictor, for measured raw IMU with known frame conventions.
/// No sensor data are fabricated; real aircraft capability must be checked separately.
public struct InertialEstimator {
    public enum MeasurementResult: Equatable {
        case accepted(nis: Double)
        case rejectedOutlier(nis: Double)
        case invalid
    }

    private var state = ASInertialState()
    public init() {}

    public var pose: SpatialPose3? {
        guard state.initialized != 0 else { return nil }
        return SpatialPose3(position: SpatialVector(east: state.position_m.x,
                                                      north: state.position_m.y,
                                                      up: state.position_m.z),
                             orientation: SpatialQuaternion(w: state.body_to_enu.w,
                                                             x: state.body_to_enu.x,
                                                             y: state.body_to_enu.y,
                                                             z: state.body_to_enu.z))
    }

    public var velocity: SpatialVector? {
        guard state.initialized != 0 else { return nil }
        return SpatialVector(east: state.velocity_mps.x, north: state.velocity_mps.y,
                             up: state.velocity_mps.z)
    }

    /// Row-major 15x15 error covariance. Caller must respect position (m),
    /// velocity (m/s), attitude (rad), and bias units.
    public var errorCovariance: [Double]? {
        guard state.initialized != 0 else { return nil }
        return withUnsafeBytes(of: state.covariance) { bytes in
            Array(bytes.bindMemory(to: Double.self))
        }
    }

    public var lastTimestampSeconds: Double? {
        state.initialized != 0 ? state.last_time_s : nil
    }

    public mutating func initialize(at seconds: Double, pose: SpatialPose3,
                                    initialStandardDeviations: [Double]) -> Bool {
        guard initialStandardDeviations.count == 5 else { return false }
        return initialStandardDeviations.withUnsafeBufferPointer {
            as_inertial_initialize(&state, seconds, pose.native, $0.baseAddress) == AS_OK
        }
    }

    /// Predicts only when a real raw-IMU sample is available, in the correct body frame.
    @discardableResult
    public mutating func predict(at seconds: Double, specificForce: SpatialVector,
                                 angularVelocityRadians: SpatialVector, noise: InertialNoise) -> Bool {
        as_inertial_predict(&state, seconds,
                            ASVector3(x: specificForce.east, y: specificForce.north,
                                      z: specificForce.up),
                            ASVector3(x: angularVelocityRadians.east,
                                      y: angularVelocityRadians.north,
                                      z: angularVelocityRadians.up),
                            noise.native) == AS_OK
    }

    @discardableResult
    public mutating func observePosition(_ position: SpatialVector,
                                         standardDeviationMeters: Double,
                                         maximumNIS: Double = 11.3449) -> MeasurementResult {
        var nis = 0.0
        let status = as_inertial_update_position(&state,
                    ASVector3(x: position.east, y: position.north, z: position.up),
                    standardDeviationMeters, maximumNIS, &nis)
        switch status {
        case AS_OK: return .accepted(nis: nis)
        case AS_OUTLIER_REJECTED: return .rejectedOutlier(nis: nis)
        default: return .invalid
        }
    }
}
