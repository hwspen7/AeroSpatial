import Foundation

public struct TrackingSettings: Equatable, Sendable {
    public var pitchGain: Double
    public var invertPitch: Bool
    public var deadZoneDegrees: Double
    public var filterTimeConstant: Double
    public var maximumPitchSpeed: Double
    public var commandInterval: Double
    public var staleAfter: Double
    public var minimumPitch: Double
    public var maximumPitch: Double

    public init(pitchGain: Double = 0.85,
                invertPitch: Bool = false,
                deadZoneDegrees: Double = 2.0,
                filterTimeConstant: Double = 0.24,
                maximumPitchSpeed: Double = 20,
                commandInterval: Double = 0.15,
                staleAfter: Double = 0.40,
                minimumPitch: Double = -85,
                maximumPitch: Double = 0) {
        self.pitchGain = pitchGain
        self.invertPitch = invertPitch
        self.deadZoneDegrees = deadZoneDegrees
        self.filterTimeConstant = filterTimeConstant
        self.maximumPitchSpeed = maximumPitchSpeed
        self.commandInterval = commandInterval
        self.staleAfter = staleAfter
        self.minimumPitch = minimumPitch
        self.maximumPitch = maximumPitch
    }
}

public enum TrackingStatus: String, Equatable, Sendable {
    case command
    case waitingForCalibration
    case disarmed
    case disconnected
    case staleMotion
    case invalidInput
    case rateLimited
}

public struct TrackingDecision: Equatable, Sendable {
    public let status: TrackingStatus
    public let pitchDegrees: Double?

    public init(status: TrackingStatus, pitchDegrees: Double? = nil) {
        self.status = status
        self.pitchDegrees = pitchDegrees
    }
}

public struct HeadTrackingController: Sendable {
    public var settings: TrackingSettings

    private var calibration: HeadSample?
    private var initialGimbalPitch: Double = 0
    private var filteredPitch: Double?
    private var lastCommandUptime: TimeInterval?

    public init(settings: TrackingSettings = TrackingSettings()) {
        self.settings = settings
    }

    public var calibrated: Bool { calibration != nil }

    public mutating func calibrate(using sample: HeadSample, currentGimbalPitch: Double) {
        guard sample.pose.isFinite, sample.uptime.isFinite, currentGimbalPitch.isFinite else { return }
        calibration = sample
        initialGimbalPitch = max(settings.minimumPitch, min(settings.maximumPitch, currentGimbalPitch))
        filteredPitch = initialGimbalPitch
        lastCommandUptime = nil
    }

    public mutating func reset() {
        calibration = nil
        filteredPitch = nil
        lastCommandUptime = nil
    }

    /// Absolute-angle commands are sent only after all software interlocks pass.
    /// The controller never produces flight/motor commands.
    public mutating func update(sample: HeadSample?, now: TimeInterval,
                                armed: Bool, aircraftConnected: Bool) -> TrackingDecision {
        guard armed else { return TrackingDecision(status: .disarmed) }
        guard aircraftConnected else { return TrackingDecision(status: .disconnected) }
        guard let baseline = calibration else { return TrackingDecision(status: .waitingForCalibration) }
        guard let sample = sample,
              now.isFinite, sample.uptime.isFinite, sample.pose.isFinite,
              settings.pitchGain.isFinite, settings.pitchGain >= 0,
              settings.deadZoneDegrees.isFinite,
              settings.filterTimeConstant.isFinite, settings.maximumPitchSpeed.isFinite,
              settings.minimumPitch.isFinite, settings.maximumPitch.isFinite,
              settings.minimumPitch < settings.maximumPitch,
              settings.commandInterval.isFinite, settings.staleAfter.isFinite,
              settings.commandInterval > 0, settings.staleAfter > 0,
              settings.maximumPitchSpeed > 0, settings.filterTimeConstant >= 0,
              settings.deadZoneDegrees >= 0 else {
            return TrackingDecision(status: .invalidInput)
        }
        let age = now - sample.uptime
        guard age >= -0.05, age <= settings.staleAfter else {
            return TrackingDecision(status: .staleMotion)
        }
        if let last = lastCommandUptime, now < last {
            return TrackingDecision(status: .invalidInput)
        }
        if let last = lastCommandUptime, now - last < settings.commandInterval {
            return TrackingDecision(status: .rateLimited)
        }
        let rawDelta = Angle.signedDegrees(sample.pose.pitch - baseline.pose.pitch)
        let magnitude = max(0, abs(rawDelta) - settings.deadZoneDegrees)
        let direction = rawDelta < 0 ? -1.0 : 1.0
        let gain = settings.pitchGain * (settings.invertPitch ? -1.0 : 1.0)
        let target = max(settings.minimumPitch, min(settings.maximumPitch,
                           initialGimbalPitch + direction * magnitude * gain))
        let interval = lastCommandUptime.map { min(1, max(0, now - $0)) } ?? settings.commandInterval
        let smoothing = settings.filterTimeConstant <= 0 ? 1.0 :
            1 - exp(-interval / settings.filterTimeConstant)
        let current = filteredPitch ?? initialGimbalPitch
        let smoothed = current + (target - current) * smoothing
        let limit = settings.maximumPitchSpeed * interval
        let next = max(settings.minimumPitch, min(settings.maximumPitch,
                   current + max(-limit, min(limit, smoothed - current))))
        filteredPitch = next
        lastCommandUptime = now
        return TrackingDecision(status: .command, pitchDegrees: next)
    }
}
