import Foundation

/// Read-only authorization assessment. This layer never sends aircraft commands.
public struct SafetySupervisor: Sendable {
    public enum BlockReason: Equatable, Sendable {
        case operatorNotAuthorized, disconnected, aircraftInFlight
        case staleHead, staleTelemetry, invalidClock, capabilityMissing
    }
    public struct Decision: Equatable, Sendable {
        public let permitted: Bool
        public let reason: BlockReason?
    }
    public var headDeadlineSeconds: Double = 0.4
    public var telemetryDeadlineSeconds: Double = 1.0

    public init() {}
    public func assess(now: Double, authorized: Bool, connected: Bool,
                       flying: Bool, lastHead: Double?, lastTelemetry: Double?,
                       pitchCapabilityVerified: Bool) -> Decision {
        func deny(_ reason: BlockReason) -> Decision { Decision(permitted: false, reason: reason) }
        guard now.isFinite, now >= 0 else { return deny(.invalidClock) }
        guard authorized else { return deny(.operatorNotAuthorized) }
        guard connected else { return deny(.disconnected) }
        guard !flying else { return deny(.aircraftInFlight) }
        guard pitchCapabilityVerified else { return deny(.capabilityMissing) }
        guard let h = lastHead, h.isFinite, h >= 0, h <= now,
              now - h <= headDeadlineSeconds else { return deny(.staleHead) }
        guard let t = lastTelemetry, t.isFinite, t >= 0, t <= now,
              now - t <= telemetryDeadlineSeconds else { return deny(.staleTelemetry) }
        return Decision(permitted: true, reason: nil)
    }
}
