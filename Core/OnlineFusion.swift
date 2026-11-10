import AeroSpatialNative
import Foundation

/// Device-neutral online inertial estimator. Never authorizes movement.
/// Requires measured IMU, synchronized timestamps, and an ENU anchor.
public final class OnlineFusion {
    public enum Outcome: Equatable { case accepted, rejectedOutlier, resetRequired, rejected }
    public struct Snapshot {
        public let pose: SpatialPose3
        public let velocity: SpatialVector
        public let covariance: [Double]
        public let report: ASFusionReport
        public let lastTimestampSeconds: Double
    }
    private let handle: OpaquePointer

    public init?(timeSeconds: Double, initialPose: SpatialPose3,
                 initialStandardDeviations: [Double], noise: InertialNoise) {
        guard initialStandardDeviations.count == 5 else { return nil }
        let nativePose = ASPose3(translation_m: ASVector3(x: initialPose.position.east,
                                            y: initialPose.position.north, z: initialPose.position.up),
                                  rotation: ASQuaternion(w: initialPose.orientation.w,
                                       x: initialPose.orientation.x, y: initialPose.orientation.y,
                                       z: initialPose.orientation.z))
        let nativeNoise = ASInertialNoise(accelerometer_std_mps2: noise.accelerometerStd,
                                         gyroscope_std_rps: noise.gyroscopeStd,
                                         accelerometer_bias_walk_mps2: noise.accelerometerBiasWalk,
                                         gyroscope_bias_walk_rps: noise.gyroscopeBiasWalk,
                                         maximum_step_s: noise.maximumStepSeconds)
        guard let ptr = initialStandardDeviations.withUnsafeBufferPointer({ stds in
            as_fusion_create(timeSeconds, nativePose, stds.baseAddress, nativeNoise)
        }) else { return nil }
        handle = ptr
    }
    deinit { as_fusion_destroy(handle) }

    private static func outcome(_ result: ASStatus) -> Outcome {
        switch result {
        case AS_OK: return .accepted
        case AS_OUTLIER_REJECTED: return .rejectedOutlier
        case AS_RESET_AFTER_GAP: return .resetRequired
        default: return .rejected
        }
    }

    public func predict(sequence: UInt64, at timeSeconds: Double, specificForce: SpatialVector,
                        angularVelocity: SpatialVector) -> Outcome {
        Self.outcome(as_fusion_imu(handle, sequence, timeSeconds,
            ASVector3(x: specificForce.east, y: specificForce.north, z: specificForce.up),
            ASVector3(x: angularVelocity.east, y: angularVelocity.north, z: angularVelocity.up)))
    }

    public func observePosition(sequence: UInt64, at timeSeconds: Double,
                                position: SpatialVector, standardDeviationMeters: Double,
                                maximumNIS: Double = 11.3449) -> Outcome {
        Self.outcome(as_fusion_position(handle, sequence, timeSeconds,
            ASVector3(x: position.east, y: position.north, z: position.up),
            standardDeviationMeters, maximumNIS))
    }

    public func snapshot() -> Snapshot? {
        var state = ASInertialState()
        var report = ASFusionReport()
        guard as_fusion_snapshot(handle, &state, &report) != 0 else { return nil }
        let pose = SpatialPose3(position: SpatialVector(east: state.position_m.x,
                                                north: state.position_m.y, up: state.position_m.z),
                                orientation: SpatialQuaternion(w: state.body_to_enu.w,
                                 x: state.body_to_enu.x, y: state.body_to_enu.y, z: state.body_to_enu.z))
        let velocity = SpatialVector(east: state.velocity_mps.x,
                                     north: state.velocity_mps.y, up: state.velocity_mps.z)
        let covariance = withUnsafeBytes(of: state.covariance) { raw in
            Array(raw.bindMemory(to: Double.self))
        }
        return Snapshot(pose: pose, velocity: velocity, covariance: covariance,
                        report: report, lastTimestampSeconds: state.last_time_s)
    }
}
