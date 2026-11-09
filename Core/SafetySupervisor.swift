import Foundation

/// Independent fail-closed check before issuing an experimental gimbal command.
/// The evaluator never sends actuator commands and is not a flight controller.
public enum SafetyDecision: String, Sendable, Equatable {
    case permitted
    case notAuthorized
    case appInactive
    case connectionLost
    case aircraftFlying
    case headUnavailable
    case headStale
    case telemetryStale
    case unverifiedHardware
    case pendingCommand
}

public struct SafetyContext: Sendable {
    public let authorized: Bool
    public let appForeground: Bool
    public let aircraftConnected: Bool
    public let aircraftFlying: Bool
    public let headAvailable: Bool
    public let headAgeSeconds: Double
    public let telemetryAgeSeconds: Double
    public let hardwarePermitted: Bool
    public let commandPending: Bool

    public init(authorized: Bool, appForeground: Bool, aircraftConnected: Bool,
                aircraftFlying: Bool, headAvailable: Bool, headAgeSeconds: Double,
                telemetryAgeSeconds: Double, hardwarePermitted: Bool,
                commandPending: Bool = false) {
        self.authorized = authorized
        self.appForeground = appForeground
        self.aircraftConnected = aircraftConnected
        self.aircraftFlying = aircraftFlying
        self.headAvailable = headAvailable
        self.headAgeSeconds = headAgeSeconds
        self.telemetryAgeSeconds = telemetryAgeSeconds
        self.hardwarePermitted = hardwarePermitted
        self.commandPending = commandPending
    }
}

public struct SafetySupervisor: Sendable {
    public let maximumHeadAgeSeconds: Double
    public let maximumTelemetryAgeSeconds: Double

    public init(maximumHeadAgeSeconds: Double = 0.4,
                maximumTelemetryAgeSeconds: Double = 1.5) {
        self.maximumHeadAgeSeconds = max(0.01, maximumHeadAgeSeconds)
        self.maximumTelemetryAgeSeconds = max(0.01, maximumTelemetryAgeSeconds)
    }

    public func evaluate(_ state: SafetyContext) -> SafetyDecision {
        if !state.appForeground { return .appInactive }
        if !state.authorized { return .notAuthorized }
        if !state.aircraftConnected { return .connectionLost }
        if state.aircraftFlying { return .aircraftFlying }
        if !state.hardwarePermitted { return .unverifiedHardware }
        if !state.headAvailable { return .headUnavailable }
        if !state.headAgeSeconds.isFinite || state.headAgeSeconds < -0.05 ||
           state.headAgeSeconds > maximumHeadAgeSeconds { return .headStale }
        if !state.telemetryAgeSeconds.isFinite || state.telemetryAgeSeconds < -0.05 ||
           state.telemetryAgeSeconds > maximumTelemetryAgeSeconds { return .telemetryStale }
        if state.commandPending { return .pendingCommand }
        return .permitted
    }
}
