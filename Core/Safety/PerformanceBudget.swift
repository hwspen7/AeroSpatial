import Foundation

/// Fixed-memory windowed latency monitor. Thresholds apply to optional work only.
public struct PerformanceBudget: Sendable {
    public struct Report: Equatable, Sendable {
        public let samples: Int
        public let p95Nanoseconds: UInt64
        public let p99Nanoseconds: UInt64
        public let maximumNanoseconds: UInt64
        public let exceedingLimit: Int
    }
    private var durations: [UInt64] = []
    private let capacity: Int
    public let maximumAllowedNanoseconds: UInt64
    public init(capacity: Int = 256, maximumAllowedNanoseconds: UInt64) {
        self.capacity = max(4, min(8192, capacity))
        self.maximumAllowedNanoseconds = maximumAllowedNanoseconds
    }
    public mutating func observe(_ durationNanoseconds: UInt64) {
        if durations.count == capacity { durations.removeFirst() }
        durations.append(durationNanoseconds)
    }
    public func report() -> Report? {
        guard !durations.isEmpty else { return nil }
        let sorted = durations.sorted()
        func percentile(_ p: Double) -> UInt64 {
            sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * p)) - 1))]
        }
        return Report(samples: sorted.count, p95Nanoseconds: percentile(0.95),
                      p99Nanoseconds: percentile(0.99),
                      maximumNanoseconds: sorted[sorted.count - 1],
                      exceedingLimit: durations.filter { $0 > maximumAllowedNanoseconds }.count)
    }
    public var isHealthy: Bool { report().map { $0.p95Nanoseconds <= maximumAllowedNanoseconds } ?? false }
}
