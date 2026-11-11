import AeroSpatialNative
import Foundation

/// Calibrates an affine transformation between two monotonic time domains.
/// Calibration is offline or low-rate because the robust initializer is quadratic.
public struct ClockPair: Equatable, Sendable {
    public let sourceSeconds: Double
    public let hostSeconds: Double
    public init(sourceSeconds: Double, hostSeconds: Double) {
        self.sourceSeconds = sourceSeconds
        self.hostSeconds = hostSeconds
    }
}

public struct ClockPrediction: Equatable, Sendable {
    public let hostSeconds: Double
    public let estimatedUncertaintySeconds: Double
}

public struct RobustClock: Sendable {
    public let scale: Double
    public let offsetSeconds: Double
    public let rmsSeconds: Double
    public let inliers: UInt32
    public let rejected: UInt32
    private let start: Double
    private let end: Double
    private let driftPPM: Double

    public static func fit(_ pairs: [ClockPair], maximumDriftPPM: Double = 200,
                           residualGateSeconds: Double = 0.02) -> RobustClock? {
        let source = pairs.map { ASClockSample(source_seconds: $0.sourceSeconds,
                                               host_seconds: $0.hostSeconds) }
        var estimate = ASClockFit()
        guard source.withUnsafeBufferPointer({ buffer in
            as_clock_fit_robust(buffer.baseAddress, buffer.count, maximumDriftPPM,
                                residualGateSeconds, &estimate)
        }) == AS_OK else { return nil }
        return RobustClock(scale: estimate.scale, offsetSeconds: estimate.offset_seconds,
                           rmsSeconds: estimate.residual_rms_seconds, inliers: estimate.inliers,
                           rejected: estimate.rejected, start: estimate.first_source_seconds,
                           end: estimate.last_source_seconds, driftPPM: estimate.drift_uncertainty_ppm)
    }

    public func translate(sourceSeconds: Double, maximumExtrapolationSeconds: Double = 0) -> ClockPrediction? {
        var fit = ASClockFit(scale: scale, offset_seconds: offsetSeconds,
                             residual_rms_seconds: rmsSeconds, first_source_seconds: start,
                             last_source_seconds: end, drift_uncertainty_ppm: driftPPM,
                             inliers: inliers, rejected: rejected)
        var host = 0.0
        var uncertainty = 0.0
        guard as_clock_translate(&fit, sourceSeconds, maximumExtrapolationSeconds,
                                 &host, &uncertainty) == AS_OK else { return nil }
        return ClockPrediction(hostSeconds: host, estimatedUncertaintySeconds: uncertainty)
    }
}
