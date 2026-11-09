import AeroSpatialNative
import Foundation

/// Only optional perception and diagnostic quality is adjusted.
/// No flight-controller, command gate, head sensor or telemetry input is affected.
public struct AdaptivePerception: Sendable {
    public enum Quality: UInt32, Sendable { case full = 0, balanced = 1, reduced = 2, minimal = 3 }
    private var state = ASAdaptiveState()
    public init() {}

    public mutating func update(timestampNanoseconds: UInt64, pressurePermille: UInt32,
                                thermalLevel: UInt32, latencyMilliseconds: Double,
                                budgetMilliseconds: Double) -> Quality? {
        var quality: UInt32 = 0
        guard as_adaptive_update(&state, timestampNanoseconds, pressurePermille, thermalLevel,
                                 latencyMilliseconds, budgetMilliseconds, &quality) == AS_OK else {
            return nil
        }
        return Quality(rawValue: quality)
    }
}

/// A visual indication of intended look direction, never a gimbal/flight command.
public struct HeadIntentPreview: Sendable, Equatable {
    public let yawDegrees: Double
    public let pitchDegrees: Double
    public let yawRateDegreesPerSecond: Double
    public let pitchRateDegreesPerSecond: Double
}

public struct HeadIntentPredictor: Sendable {
    private var state = ASHeadIntentState()
    public init() {}

    public mutating func observe(seconds: Double, yawDegrees: Double, pitchDegrees: Double,
                                 horizonSeconds: Double = 0.1) -> HeadIntentPreview? {
        var value = ASHeadIntentPrediction()
        guard as_head_intent_predict(&state, seconds, yawDegrees, pitchDegrees,
                                     horizonSeconds, &value) == AS_OK else { return nil }
        return HeadIntentPreview(yawDegrees: value.predicted_yaw_deg,
                                 pitchDegrees: value.predicted_pitch_deg,
                                 yawRateDegreesPerSecond: value.yaw_rate_deg_s,
                                 pitchRateDegreesPerSecond: value.pitch_rate_deg_s)
    }
}
