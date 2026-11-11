import Foundation

public enum GimbalAxis: String, Codable, CaseIterable, Sendable {
    case pitch
    case yaw
    case roll
}

public struct DeviceCapabilities: Equatable, Codable, Sendable {
    public let deviceIdentifier: String
    public let provenance: AircraftSource
    public let gimbalAxes: Set<GimbalAxis>
    public let canReadTelemetry: Bool
    public let canReadVideo: Bool
    public let canCommandFlight: Bool

    public init(deviceIdentifier: String, provenance: AircraftSource,
                gimbalAxes: Set<GimbalAxis>, canReadTelemetry: Bool,
                canReadVideo: Bool = false) {
        self.deviceIdentifier = deviceIdentifier
        self.provenance = provenance
        self.gimbalAxes = gimbalAxes
        self.canReadTelemetry = canReadTelemetry
        self.canReadVideo = canReadVideo
        canCommandFlight = false
    }

    public static let simulator = DeviceCapabilities(
        deviceIdentifier: "simulator", provenance: .simulator,
        gimbalAxes: [.pitch], canReadTelemetry: true)

    /// Conservative initial status until the SDK gimbal and controller are verified.
    public static let unverifiedDJI = DeviceCapabilities(
        deviceIdentifier: "dji-msdk-v4-unverified", provenance: .dji,
        gimbalAxes: [], canReadTelemetry: false)

    public func allowsPitchCommand(connected: Bool, hardwareVerified: Bool) -> Bool {
        connected && gimbalAxes.contains(.pitch) &&
        (provenance == .simulator || hardwareVerified)
    }
}
