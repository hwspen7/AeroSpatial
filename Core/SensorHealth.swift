import Foundation

public enum StreamFreshness: String, Sendable, Equatable {
    case missing
    case fresh
    case stale
}

public enum SampleVerdict: String, Sendable, Equatable {
    case accepted
    case invalid
    case outOfOrder
    case futureTimestamp
}

public struct StreamStatistics: Equatable, Sendable {
    public let accepted: Int
    public let rejected: Int
    public let observedGaps: Int
    public let lastUptime: Double?
    public let freshness: StreamFreshness
}

struct MonotonicStream: Sendable {
    var accepted = 0
    var rejected = 0
    var gaps = 0
    var last: Double?

    mutating func observe(timestamp: Double, now: Double,
                          valid: Bool, gapThreshold: Double) -> SampleVerdict {
        guard valid, timestamp.isFinite, now.isFinite, timestamp >= 0,
              gapThreshold.isFinite, gapThreshold > 0 else {
            rejected += 1
            return .invalid
        }
        guard timestamp <= now + 0.05 else {
            rejected += 1
            return .futureTimestamp
        }
        guard last.map({ timestamp > $0 }) ?? true else {
            rejected += 1
            return .outOfOrder
        }
        if let last, timestamp - last > gapThreshold { gaps += 1 }
        self.last = timestamp
        accepted += 1
        return .accepted
    }

    func snapshot(now: Double, staleAfter: Double) -> StreamStatistics {
        let status: StreamFreshness
        if let last, now.isFinite, now >= last,
           staleAfter.isFinite, staleAfter > 0 {
            status = now - last <= staleAfter ? .fresh : .stale
        } else {
            status = .missing
        }
        return StreamStatistics(accepted: accepted, rejected: rejected,
                                observedGaps: gaps, lastUptime: last, freshness: status)
    }
}

/// Estimates only temporal stream quality. It cannot certify sensor accuracy.
public struct SensorHealthMonitor: Sendable {
    public var headGapThreshold = 0.25
    public var telemetryGapThreshold = 1.0
    public var headStaleAfter = 0.40
    public var telemetryStaleAfter = 2.0
    private var head = MonotonicStream()
    private var telemetry = MonotonicStream()

    public init() {}

    public mutating func reset() {
        head = MonotonicStream()
        telemetry = MonotonicStream()
    }

    @discardableResult
    public mutating func observeHead(_ sample: HeadSample, receivedAt now: Double) -> SampleVerdict {
        head.observe(timestamp: sample.uptime, now: now, valid: sample.pose.isFinite,
                     gapThreshold: headGapThreshold)
    }

    @discardableResult
    public mutating func observeAircraft(_ sample: AircraftSnapshot,
                                         receivedAt now: Double) -> SampleVerdict {
        telemetry.observe(timestamp: sample.uptime, now: now, valid: sample.isValid,
                          gapThreshold: telemetryGapThreshold)
    }

    public func health(at now: Double) -> (head: StreamStatistics, aircraft: StreamStatistics) {
        (head.snapshot(now: now, staleAfter: headStaleAfter),
         telemetry.snapshot(now: now, staleAfter: telemetryStaleAfter))
    }
}
