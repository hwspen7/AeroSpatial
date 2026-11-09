import Foundation

/// Bounded affine mapping from a remote monotonic clock to local uptime.
/// This estimator is for observation alignment, not command authorization.
public struct ClockBridge: Sendable {
    public enum Decision: Equatable, Sendable {
        case accepted
        case rejectedOutlier
        case rejectedNonMonotonic
        case invalid
    }

    public private(set) var scale: Double = 1
    public private(set) var offset: Double = 0
    public private(set) var count: Int = 0
    private var lastRemote: Double?
    private var lastLocal: Double?
    private let maximumDriftPPM: Double
    private let outlierSeconds: Double

    public init(maximumDriftPPM: Double = 200, outlierSeconds: Double = 0.12) {
        self.maximumDriftPPM = max(1, maximumDriftPPM)
        self.outlierSeconds = max(0.001, outlierSeconds)
    }

    public mutating func observe(remote: Double, local: Double) -> Decision {
        guard remote.isFinite, local.isFinite, remote >= 0, local >= 0 else { return .invalid }
        if let r = lastRemote, let l = lastLocal {
            guard remote > r, local > l else { return .rejectedNonMonotonic }
            let predicted = scale * remote + offset
            guard abs(predicted - local) <= outlierSeconds else { return .rejectedOutlier }
            let observedScale = (local - l) / (remote - r)
            let limit = maximumDriftPPM * 1e-6
            if observedScale.isFinite && observedScale >= 1 - limit && observedScale <= 1 + limit {
                scale = max(1 - limit, min(1 + limit, 0.98 * scale + 0.02 * observedScale))
            }
            offset = 0.98 * offset + 0.02 * (local - scale * remote)
        } else {
            offset = local - remote
        }
        lastRemote = remote
        lastLocal = local
        count += 1
        return .accepted
    }

    public func translate(remote: Double) -> Double? {
        guard count > 0, remote.isFinite, remote >= 0 else { return nil }
        let result = scale * remote + offset
        return result.isFinite ? result : nil
    }
}
