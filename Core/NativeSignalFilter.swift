import Foundation
import AeroSpatialNative

public enum FilterOutcome: Equatable, Sendable {
    case accepted(Double)
    case resetAfterGap(Double)
    case outOfOrder
    case outlier
    case invalid
}

/// Value-type wrapper around a C++ alpha-beta filter. No threads, allocations, or IO.
public struct NativeSignalFilter: Sendable {
    public let alpha: Double
    public let beta: Double
    public let maximumGapSeconds: Double
    public let maximumInnovation: Double
    private var native = ASFilterState(position: 0, velocity: 0, last_time: 0, initialized: 0)

    public init(alpha: Double = 0.5, beta: Double = 0.1,
                maximumGapSeconds: Double = 1.0, maximumInnovation: Double = 45) {
        self.alpha = alpha
        self.beta = beta
        self.maximumGapSeconds = maximumGapSeconds
        self.maximumInnovation = maximumInnovation
    }

    public var position: Double? { native.initialized == 0 ? nil : native.position }
    public var velocity: Double? { native.initialized == 0 ? nil : native.velocity }

    public mutating func reset() { as_filter_reset(&native) }

    public mutating func observe(value: Double, at uptime: TimeInterval) -> FilterOutcome {
        var output = 0.0
        switch as_filter_update(&native, uptime, value, alpha, beta,
                                maximumGapSeconds, maximumInnovation, &output) {
        case AS_OK: return .accepted(output)
        case AS_RESET_AFTER_GAP: return .resetAfterGap(output)
        case AS_OUT_OF_ORDER: return .outOfOrder
        case AS_OUTLIER_REJECTED: return .outlier
        default: return .invalid
        }
    }
}
