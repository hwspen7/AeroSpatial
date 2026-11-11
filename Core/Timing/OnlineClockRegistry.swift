import Foundation

/// Rolling clock calibration, only for observation alignment, never command safety.
public actor OnlineClockRegistry {
    public enum Update: Equatable, Sendable { case accepted, outlier, invalid, regression }
    public struct Prediction: Equatable, Sendable {
        public let alignedNanoseconds: UInt64
        public let uncertaintyNanoseconds: UInt64
        public let calibrationSamples: Int
    }
    private struct Domain {
        var samples: [ClockPair] = []
        var latestSource: Double = -1
        var latestHost: Double = -1
        var estimate: RobustClock?
    }
    private var domains: [UInt32: Domain] = [:]
    private let window: Int
    private let driftPPM: Double
    private let residualGate: Double

    public init(window: Int = 48, driftPPM: Double = 200, residualGateSeconds: Double = 0.025) {
        self.window = max(4, min(128, window))
        self.driftPPM = max(1, min(2000, driftPPM))
        self.residualGate = max(0.001, min(1, residualGateSeconds))
    }

    @discardableResult
    public func observe(domain: UInt32, sourceSeconds: Double, hostSeconds: Double) -> Update {
        guard domain > 0, sourceSeconds.isFinite, hostSeconds.isFinite,
              sourceSeconds >= 0, hostSeconds >= 0 else { return .invalid }
        var current = domains[domain] ?? Domain()
        guard sourceSeconds > current.latestSource, hostSeconds > current.latestHost else { return .regression }
        if let fit = current.estimate,
           let prediction = fit.translate(sourceSeconds: sourceSeconds, maximumExtrapolationSeconds: 2),
           abs(prediction.hostSeconds - hostSeconds) > residualGate + prediction.estimatedUncertaintySeconds {
            return .outlier
        }
        current.samples.append(ClockPair(sourceSeconds: sourceSeconds, hostSeconds: hostSeconds))
        if current.samples.count > window { current.samples.removeFirst() }
        current.latestSource = sourceSeconds
        current.latestHost = hostSeconds
        if current.samples.count >= 4 && (current.estimate == nil || current.samples.count % 4 == 0) {
            current.estimate = RobustClock.fit(current.samples, maximumDriftPPM: driftPPM,
                                               residualGateSeconds: residualGate)
        }
        domains[domain] = current
        return .accepted
    }

    public func translate(domain: UInt32, sourceSeconds: Double,
                          maximumExtrapolationSeconds: Double = 0.25,
                          maximumUncertaintySeconds: Double = 0.025) -> Prediction? {
        guard domain > 0, sourceSeconds.isFinite, sourceSeconds >= 0,
              maximumUncertaintySeconds.isFinite, maximumUncertaintySeconds > 0,
              let current = domains[domain], let fit = current.estimate,
              let prediction = fit.translate(sourceSeconds: sourceSeconds,
                                             maximumExtrapolationSeconds: maximumExtrapolationSeconds),
              prediction.hostSeconds >= 0, prediction.estimatedUncertaintySeconds >= 0,
              prediction.estimatedUncertaintySeconds <= maximumUncertaintySeconds,
              prediction.hostSeconds < Double(UInt64.max) / 1e9,
              prediction.estimatedUncertaintySeconds < Double(UInt64.max) / 1e9 else { return nil }
        return Prediction(alignedNanoseconds: UInt64(prediction.hostSeconds * 1e9),
                          uncertaintyNanoseconds: UInt64(ceil(prediction.estimatedUncertaintySeconds * 1e9)),
                          calibrationSamples: current.samples.count)
    }

    public func reset(domain: UInt32) { domains[domain] = nil }
}
