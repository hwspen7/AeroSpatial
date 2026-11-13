import AeroSpatialNative
import Foundation

/// Admission control for optional work only. Never gates failsafes or commands.
/// The native handle is synchronized internally; destroy it only after callers stop.
public final class ComputeGovernor: @unchecked Sendable {
    private let handle: OpaquePointer

    public init?() {
        guard let handle = as_qos_create() else { return nil }
        self.handle = handle
    }

    deinit { as_qos_destroy(handle) }

    public func configure(stream: SpatialStream, refillUnitsPerSecond: Double,
                          burstUnits: Double, maximumPressurePermille: UInt32) -> Bool {
        guard stream == .video || stream == .perception || stream == .diagnostic else { return false }
        let policy = ASQosPolicy(stream_id: stream.rawValue,
                                 refill_units_per_second: refillUnitsPerSecond,
                                 burst_units: burstUnits,
                                 maximum_pressure_permille: maximumPressurePermille)
        return as_qos_configure(handle, policy) == ASQOS_ADMITTED
    }

    public enum Decision: Sendable, Equatable {
        case admitted, rateLimited, backlogged, invalid, timeRegression
    }

    public func admit(stream: SpatialStream, timestampNanoseconds: UInt64,
                      estimatedUnits: Double, pressurePermille: UInt32) -> Decision {
        switch as_qos_admit(handle, stream.rawValue, timestampNanoseconds,
                            estimatedUnits, pressurePermille) {
        case ASQOS_ADMITTED: return .admitted
        case ASQOS_RATE_LIMITED: return .rateLimited
        case ASQOS_BACKLOGGED: return .backlogged
        case ASQOS_TIME_REGRESSION: return .timeRegression
        default: return .invalid
        }
    }

    public func stats(stream: SpatialStream) -> ComputeStats? {
        var result = ASQosStats()
        guard as_qos_stats(handle, stream.rawValue, &result) == ASQOS_ADMITTED else { return nil }
        return ComputeStats(seen: result.seen, admitted: result.admitted,
                            rateLimited: result.rate_limited, backlogged: result.backlogged,
                            invalid: result.invalid, availableUnits: result.available_units)
    }
}

public struct ComputeStats: Equatable, Sendable {
    public let seen: UInt64
    public let admitted: UInt64
    public let rateLimited: UInt64
    public let backlogged: UInt64
    public let invalid: UInt64
    public let availableUnits: Double
}
