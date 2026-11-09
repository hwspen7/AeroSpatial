import Foundation

/// Constant-memory latency histogram and loss counters for optional workload monitoring.
/// Buckets are exponential in microseconds; no dynamic storage per observation.
public struct RuntimeMetrics: Sendable {
    private var buckets = Array(repeating: UInt64(0), count: 32)
    private(set) public var samples: UInt64 = 0
    private(set) public var invalid: UInt64 = 0
    private(set) public var rejected: UInt64 = 0
    private(set) public var lastDurationMicroseconds: UInt64 = 0
    private(set) public var maxDurationMicroseconds: UInt64 = 0

    public init() {}

    public mutating func observe(durationSeconds: Double, accepted: Bool = true) {
        guard durationSeconds.isFinite, durationSeconds >= 0,
              durationSeconds < Double(UInt64.max / 1_000_000) else {
            invalid &+= 1
            return
        }
        let micros = UInt64(durationSeconds * 1_000_000)
        lastDurationMicroseconds = micros
        maxDurationMicroseconds = max(maxDurationMicroseconds, micros)
        let bin = micros == 0 ? 0 : min(31, 64 - micros.leadingZeroBitCount)
        buckets[bin] &+= 1
        samples &+= 1
        if !accepted { rejected &+= 1 }
    }

    public func upperBoundMicroseconds(percentile: Double) -> UInt64? {
        guard samples > 0, percentile.isFinite,
              percentile > 0 && percentile <= 1 else { return nil }
        let rank = max(UInt64(1), UInt64(ceil(Double(samples) * percentile)))
        var total: UInt64 = 0
        for (index, count) in buckets.enumerated() {
            total &+= count
            if total >= rank { return index == 0 ? 0 : UInt64(1) << index }
        }
        return nil
    }

    public func exceedsLatencyBudget(_ budgetMicroseconds: UInt64,
                                     minimumSamples: UInt64 = 100) -> Bool {
        samples >= minimumSamples &&
        (upperBoundMicroseconds(percentile: 0.95) ?? 0) > budgetMicroseconds
    }
}
