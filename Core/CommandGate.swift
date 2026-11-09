import Foundation

/// A short-lived ticket. An old asynchronous callback cannot complete a new command.
public struct CommandTicket: Equatable, Sendable {
    public let generation: UInt64
    public let sequence: UInt64
    public let issuedAt: TimeInterval
    public let targetPitch: Double
}

public enum CommandBlock: String, Equatable, Sendable {
    case notAuthorized
    case disconnected
    case aircraftFlying
    case headStale
    case telemetryStale
    case pending
    case faultLatched
    case invalidInput
}

public enum CommandAdmission: Equatable, Sendable {
    case granted(CommandTicket)
    case blocked(CommandBlock)
}

public enum CommandCompletion: Equatable, Sendable {
    case completed
    case rejected
    case ignored
}

/// A fail-closed command gate for gimbal pitch only. Never issues flight commands.
/// This gate is separate from the numeric tracking controller and the DJI adapter.
public struct GimbalCommandGate: Sendable {
    public var maximumHeadAge: Double = 0.40
    public var maximumTelemetryAge: Double = 2.0
    public var acknowledgementTimeout: Double = 1.0
    private(set) public var pending: CommandTicket?
    private(set) public var faultLatched = false
    private var generation: UInt64 = 0
    private var nextSequence: UInt64 = 0

    public init() {}

    /// Called on every explicit arm/disarm or hardware-mode transition.
    public mutating func reset() {
        generation &+= 1
        nextSequence = 0
        pending = nil
        faultLatched = false
    }

    /// Returns true once the pending command exceeds the callback deadline.
    @discardableResult
    public mutating func checkTimeout(now: TimeInterval) -> Bool {
        guard let ticket = pending, now.isFinite, acknowledgementTimeout.isFinite,
              acknowledgementTimeout > 0, now >= ticket.issuedAt,
              now - ticket.issuedAt > acknowledgementTimeout else { return false }
        pending = nil
        faultLatched = true
        return true
    }

    public mutating func request(now: TimeInterval, pitch: Double,
                                 authorized: Bool, connected: Bool, aircraftFlying: Bool,
                                 headTimestamp: TimeInterval?,
                                 telemetryTimestamp: TimeInterval?) -> CommandAdmission {
        guard now.isFinite, pitch.isFinite, (-90...30).contains(pitch),
              maximumHeadAge.isFinite, maximumHeadAge > 0,
              maximumTelemetryAge.isFinite, maximumTelemetryAge > 0,
              acknowledgementTimeout.isFinite, acknowledgementTimeout > 0 else {
            return .blocked(.invalidInput)
        }
        if checkTimeout(now: now) { return .blocked(.faultLatched) }
        guard !faultLatched else { return .blocked(.faultLatched) }
        guard authorized else { return .blocked(.notAuthorized) }
        guard connected else { return .blocked(.disconnected) }
        guard !aircraftFlying else { return .blocked(.aircraftFlying) }
        guard let head = headTimestamp, head.isFinite, now - head >= -0.05,
              now - head <= maximumHeadAge else { return .blocked(.headStale) }
        guard let telemetry = telemetryTimestamp, telemetry.isFinite, now - telemetry >= -0.05,
              now - telemetry <= maximumTelemetryAge else { return .blocked(.telemetryStale) }
        guard pending == nil else { return .blocked(.pending) }
        let ticket = CommandTicket(generation: generation, sequence: nextSequence,
                                   issuedAt: now, targetPitch: pitch)
        nextSequence &+= 1
        pending = ticket
        return .granted(ticket)
    }

    /// A non-matching callback is ignored, including a callback after disarm.
    public mutating func complete(_ ticket: CommandTicket, now: TimeInterval,
                                  succeeded: Bool) -> CommandCompletion {
        guard pending == ticket else { return .ignored }
        guard now.isFinite, now >= ticket.issuedAt,
              !checkTimeout(now: now) else {
            faultLatched = true
            pending = nil
            return .rejected
        }
        pending = nil
        if succeeded { return .completed }
        faultLatched = true
        return .rejected
    }
}
