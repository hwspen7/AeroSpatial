import Foundation

/// Conservative capability evaluation. This is advisory planning, never a flight authorization.
public enum AlgorithmDeployment {
    public enum Decision: Equatable, Sendable {
        case supported
        case missingHeadSensor
        case missingTelemetry
        case missingVideo
        case unverifiedHardware
    }

    public static func evaluate(_ algorithm: AlgorithmManifest,
                                device: DeviceCapabilities,
                                hasHeadMotion: Bool,
                                hardwareVerified: Bool) -> Decision {
        if algorithm.requiresHardware && !hardwareVerified { return .unverifiedHardware }
        if algorithm.inputs.contains(.head) && !hasHeadMotion { return .missingHeadSensor }
        if algorithm.inputs.contains(.telemetry) && !device.canReadTelemetry {
            return .missingTelemetry
        }
        if algorithm.inputs.contains(.video) && !device.canReadVideo { return .missingVideo }
        return .supported
    }
}
