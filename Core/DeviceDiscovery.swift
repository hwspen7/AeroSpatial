import Foundation

/// Device claims never become verified capabilities without an explicit observation.
public struct DeviceEvidence: Sendable, Equatable {
    public let identifier: String
    public let firmware: String
    public let observedAt: TimeInterval
    public let axes: Set<GimbalAxis>
    public let telemetry: Bool
    public let video: Bool
    public let verified: Bool

    public init?(identifier: String, firmware: String, observedAt: TimeInterval,
                 axes: Set<GimbalAxis>, telemetry: Bool, video: Bool, verified: Bool) {
        guard !identifier.isEmpty, identifier.count <= 128, firmware.count <= 128,
              observedAt.isFinite, observedAt >= 0 else { return nil }
        self.identifier = identifier
        self.firmware = firmware
        self.observedAt = observedAt
        self.axes = axes
        self.telemetry = telemetry
        self.video = video
        self.verified = verified
    }

    public func capabilities(source: AircraftSource) -> DeviceCapabilities {
        DeviceCapabilities(deviceIdentifier: identifier, provenance: source,
                           gimbalAxes: verified ? axes : [],
                           canReadTelemetry: verified && telemetry,
                           canReadVideo: verified && video)
    }
}

public actor DeviceDiscovery {
    private var last: DeviceEvidence?
    public init() {}
    public func record(_ evidence: DeviceEvidence) {
        if let previous = last, evidence.observedAt < previous.observedAt { return }
        last = evidence
    }
    public func resolve(now: TimeInterval, maxAge: TimeInterval = 2,
                        source: AircraftSource = .dji) -> DeviceCapabilities {
        guard let evidence = last, now.isFinite, maxAge.isFinite, maxAge >= 0,
              now >= evidence.observedAt, now - evidence.observedAt <= maxAge else {
            return .unverifiedDJI
        }
        return evidence.capabilities(source: source)
    }
    public func invalidate() { last = nil }
}
