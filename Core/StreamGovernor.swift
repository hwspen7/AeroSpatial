import Foundation

/// Non-safety-critical stream pacing for visual updates and analytics.
/// Control admission and aircraft command timing never depend on this class.
public struct StreamGovernor: Sendable {
    public struct Configuration: Sendable {
        public let minimumInterval: Double
        public let maximumInterval: Double
        public let targetProcessingSeconds: Double
        public let backoffMultiplier: Double

        public init(minimumInterval: Double = 1.0 / 60, maximumInterval: Double = 0.25,
                    targetProcessingSeconds: Double = 0.008, backoffMultiplier: Double = 1.4) {
            self.minimumInterval = max(0.001, minimumInterval)
            self.maximumInterval = max(self.minimumInterval, maximumInterval)
            self.targetProcessingSeconds = max(0.001, targetProcessingSeconds)
            self.backoffMultiplier = max(1.01, backoffMultiplier)
        }
    }

    private let config: Configuration
    public private(set) var interval: Double
    private var lastPublished: Double?
    private var estimatedCost = 0.0
    public private(set) var admittedCount = 0
    public private(set) var skippedCount = 0

    public init(config: Configuration = Configuration()) {
        self.config = config
        interval = config.minimumInterval
    }

    public mutating func observeProcessing(seconds: Double, backlogged: Bool) {
        guard seconds.isFinite, seconds >= 0 else { return }
        estimatedCost = estimatedCost == 0 ? seconds : 0.15 * seconds + 0.85 * estimatedCost
        if backlogged || estimatedCost > config.targetProcessingSeconds {
            interval = min(config.maximumInterval, interval * config.backoffMultiplier)
        } else {
            interval = max(config.minimumInterval, interval * 0.98)
        }
    }

    public mutating func shouldPublish(at uptime: Double, important: Bool = false) -> Bool {
        guard uptime.isFinite, uptime >= 0 else { return false }
        if let previous = lastPublished, uptime < previous { return false }
        if !important, let previous = lastPublished, uptime - previous < interval {
            skippedCount += 1
            return false
        }
        lastPublished = uptime
        admittedCount += 1
        return true
    }

    public mutating func reset() {
        interval = config.minimumInterval
        estimatedCost = 0
        lastPublished = nil
        admittedCount = 0
        skippedCount = 0
    }
}
