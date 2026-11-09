import Foundation

/// Report what a connected adapter actually observes, without treating presence
/// of a hardware component as proof of safe actuator control.
public struct CapabilityEvidence: Sendable, Equatable {
    public let productModel: String
    public let connected: Bool
    public let flightControllerPresent: Bool
    public let cameraPresent: Bool
    public let gimbalPresent: Bool
    public let source: AircraftSource

    public init(productModel: String, connected: Bool, flightControllerPresent: Bool,
                cameraPresent: Bool, gimbalPresent: Bool, source: AircraftSource) {
        self.productModel = productModel
        self.connected = connected
        self.flightControllerPresent = flightControllerPresent
        self.cameraPresent = cameraPresent
        self.gimbalPresent = gimbalPresent
        self.source = source
    }

    /// Device discovery is read-only. Pitch actuation remains unverified for DJI.
    public var observedCapabilities: DeviceCapabilities {
        DeviceCapabilities(deviceIdentifier: productModel, provenance: source,
                           gimbalAxes: source == .simulator && gimbalPresent ? [.pitch] : [],
                           canReadTelemetry: connected && flightControllerPresent,
                           canReadVideo: connected && cameraPresent)
    }
}
