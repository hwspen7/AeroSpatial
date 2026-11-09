import Foundation

/// Conservative time-error budget for explicitly calibrated clock mappings.
/// This is observation metadata, not a flight-control deadline guarantee.
public struct ClockUncertainty: Sendable, Equatable {
    public let alignedSeconds: Double
    public let maximumErrorSeconds: Double

    public init?(alignedSeconds: Double, maximumErrorSeconds: Double) {
        guard alignedSeconds.isFinite, alignedSeconds >= 0,
              maximumErrorSeconds.isFinite, maximumErrorSeconds >= 0 else { return nil }
        self.alignedSeconds = alignedSeconds
        self.maximumErrorSeconds = maximumErrorSeconds
    }
}

public extension ClockBridge {
    /// An explicit error envelope, allowing for drift since the last calibration.
    /// Caller must supply an empirically justified synchronization error bound.
    func estimate(remote: Double, referenceRemote: Double,
                  calibrationErrorSeconds: Double,
                  driftPPM: Double = 200) -> ClockUncertainty? {
        guard referenceRemote.isFinite, referenceRemote >= 0,
              calibrationErrorSeconds.isFinite, calibrationErrorSeconds >= 0,
              driftPPM.isFinite, driftPPM >= 0,
              let translated = translate(remote: remote) else { return nil }
        let elapsed = abs(remote - referenceRemote)
        let error = calibrationErrorSeconds + elapsed * driftPPM * 1e-6
        return ClockUncertainty(alignedSeconds: translated, maximumErrorSeconds: error)
    }
}
