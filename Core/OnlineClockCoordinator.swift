import Foundation

public enum ClockObservationDecision: Equatable, Sendable {
    case accepted
    case invalid
    case duplicateOrRegressed
    case outlier
    case resetAfterGap
}

/// Online low-rate estimation of mappings between independent monotonic clocks.
/// Every prediction includes an estimated error and an explicit freshness limit.
public struct OnlineClockCoordinator: Sendable {
    private struct State: Sendable {
        var samples: [ClockPair] = []
        var model: RobustClock?
        var lastSource: Double?
        var lastHost: Double?
        var newSinceFit = 0
    }
    private var states: [UInt32: State] = [:]
    public let maximumDomains: Int
    public let maximumSamples: Int
    public let maximumGapSeconds: Double
    public let maximumPredictionAgeSeconds: Double
    public let residualGateSeconds: Double
    public let driftPPM: Double

    public init(maximumDomains: Int = 16, maximumSamples: Int = 32,
                maximumGapSeconds: Double = 5,
                maximumPredictionAgeSeconds: Double = 2,
                residualGateSeconds: Double = 0.08, driftPPM: Double = 200) {
        self.maximumDomains = max(1, min(64, maximumDomains))
        self.maximumSamples = max(8, min(64, maximumSamples))
        self.maximumGapSeconds = max(0.2, maximumGapSeconds)
        self.maximumPredictionAgeSeconds = max(0.05, maximumPredictionAgeSeconds)
        self.residualGateSeconds = max(0.001, residualGateSeconds)
        self.driftPPM = max(1, driftPPM)
    }

    @discardableResult
    public mutating func observe(domain: UInt32, source: Double,
                                 host: Double) -> ClockObservationDecision {
        guard domain != 0, source.isFinite, source >= 0,
              host.isFinite, host >= 0 else { return .invalid }
        guard states[domain] != nil || states.count < maximumDomains else { return .invalid }
        var state = states[domain] ?? State()
        if let previous = state.lastSource, source <= previous { return .duplicateOrRegressed }
        if let previous = state.lastHost, host <= previous { return .duplicateOrRegressed }
        let gap = state.lastSource.map { source - $0 > maximumGapSeconds } ?? false
        if gap { state = State() }
        if let prediction = state.model?.translate(sourceSeconds: source,
                              maximumExtrapolationSeconds: maximumGapSeconds),
            abs(prediction.hostSeconds - host) > residualGateSeconds +
               prediction.estimatedUncertaintySeconds {
            return .outlier
        }
        state.samples.append(ClockPair(sourceSeconds: source, hostSeconds: host))
        if state.samples.count > maximumSamples { state.samples.removeFirst() }
        state.lastSource = source
        state.lastHost = host
        state.newSinceFit += 1
        if state.samples.count >= 4 && (state.model == nil || state.newSinceFit >= 4) {
            let fitted = RobustClock.fit(state.samples, maximumDriftPPM: driftPPM,
                                         residualGateSeconds: residualGateSeconds)
            if let fitted, fitted.inliers >= 4 { state.model = fitted }
            state.newSinceFit = 0
        }
        states[domain] = state
        return gap ? .resetAfterGap : .accepted
    }

    public func translate(domain: UInt32, source: Double,
                          hostNow: Double, maximumError: Double = 0.1) -> ClockUncertainty? {
        guard source.isFinite, hostNow.isFinite, hostNow >= 0,
              maximumError.isFinite, maximumError >= 0,
              let state = states[domain], let fitted = state.model,
              let last = state.lastHost, hostNow >= last,
              hostNow - last <= maximumPredictionAgeSeconds,
              let result = fitted.translate(sourceSeconds: source,
                                             maximumExtrapolationSeconds: maximumPredictionAgeSeconds),
              result.estimatedUncertaintySeconds <= maximumError else { return nil }
        return ClockUncertainty(alignedSeconds: result.hostSeconds,
                                maximumErrorSeconds: result.estimatedUncertaintySeconds)
    }

    public mutating func reset(domain: UInt32) { states.removeValue(forKey: domain) }
    public mutating func resetAll() { states.removeAll(keepingCapacity: true) }
}
