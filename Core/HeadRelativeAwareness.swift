import Foundation

public struct CompassCalibration: Equatable, Sendable {
    public let calibratedUptime: TimeInterval
    public let headYawDegrees: Double
    public let worldHeadingDegrees: Double
    public let headingAccuracyDegrees: Double

    public init?(sample: HeadSample, heading: Double, headingAccuracy: Double) {
        guard sample.pose.isFinite, sample.uptime.isFinite, heading.isFinite,
              headingAccuracy.isFinite, headingAccuracy >= 0, headingAccuracy <= 20 else { return nil }
        calibratedUptime = sample.uptime
        headYawDegrees = sample.pose.yaw
        worldHeadingDegrees = Angle.compassDegrees(heading)
        headingAccuracyDegrees = headingAccuracy
    }
}

public struct HeadRelativeCue: Equatable, Sendable {
    public let relativeBearingDegrees: Double
    public let distanceMeters: Double
    public let stereoPan: Double
    public let approximateDirection: String
}

/// Uses an explicit, short-lived head/phone-forward alignment.
/// This estimates a horizontal audio cue, not a true eye-gaze or HRTF model.
public struct HeadRelativeAwareness: Sendable {
    public var maximumCalibrationAge: TimeInterval = 120
    public var maximumHeadAge: TimeInterval = 0.4
    public var maximumPositionAge: TimeInterval = 2
    private(set) public var calibration: CompassCalibration?

    public init() {}

    public mutating func setCalibration(_ value: CompassCalibration) {
        calibration = value
    }

    public mutating func reset() { calibration = nil }

    public func cue(head: HeadSample, now: TimeInterval,
                    pilot: GeoPoint, pilotFixUptime: TimeInterval,
                    target: GeoPoint, targetFixUptime: TimeInterval) -> HeadRelativeCue? {
        guard let calibration = calibration, now.isFinite, head.uptime.isFinite,
              now >= calibration.calibratedUptime,
              now - calibration.calibratedUptime <= maximumCalibrationAge,
              now >= head.uptime, now - head.uptime <= maximumHeadAge,
              now >= pilotFixUptime, now - pilotFixUptime <= maximumPositionAge,
              now >= targetFixUptime, now - targetFixUptime <= maximumPositionAge,
              head.uptime >= calibration.calibratedUptime,
              head.pose.isFinite else { return nil }
        let estimatedHeadHeading = Angle.compassDegrees(
            calibration.worldHeadingDegrees +
            Angle.signedDegrees(head.pose.yaw - calibration.headYawDegrees))
        guard let position = Geodesy.relativePosition(
            from: pilot, to: target, observerHeadingDegrees: estimatedHeadHeading) else { return nil }
        return HeadRelativeCue(relativeBearingDegrees: position.relativeBearingDegrees,
                               distanceMeters: position.distanceMeters,
                               stereoPan: DirectionCue.stereoPan(relativeBearing: position.relativeBearingDegrees),
                               approximateDirection: DirectionCue.label(
                                relativeBearing: position.relativeBearingDegrees))
    }
}
