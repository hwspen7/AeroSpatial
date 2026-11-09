import Foundation

/// Identifiers are shared with Kernel/include/aerospatial_bus.h.
public enum SpatialStream: UInt32, CaseIterable, Sendable {
    case head = 1
    case telemetry = 2
    case video = 3
    case perception = 4
    case diagnostic = 5
}

public struct SpatialQuality: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let valid = Self(rawValue: 1 << 0)
    public static let simulated = Self(rawValue: 1 << 1)
    public static let clockEstimated = Self(rawValue: 1 << 2)
    public static let lowConfidence = Self(rawValue: 1 << 3)
    public static let stale = Self(rawValue: 1 << 4)
    public static let upstreamGap = Self(rawValue: 1 << 5)
}

public struct SpatialEvent: Sendable, Equatable {
    public let stream: SpatialStream
    public let timestampNanoseconds: UInt64
    public let sequence: UInt64
    public let clockDomain: UInt32
    public let traceID: UInt64
    public let kind: UInt32
    public let quality: SpatialQuality
    public let missed: UInt64
    public let payload: Data
}

public struct SpatialStreamStats: Sendable, Equatable {
    public let published: UInt64
    public let overwritten: UInt64
    public let rejected: UInt64
    public let invalid: UInt64
    public let retainedBytes: UInt64
    public let highWaterBytes: UInt64
    public let retainedEvents: UInt32
    public let subscribers: UInt32
    public let budgetRejected: UInt64
}

public struct SpatialMemoryStats: Sendable, Equatable {
    public let limitBytes: UInt64
    public let liveBytes: UInt64
    public let highWaterBytes: UInt64
}

public enum SpatialBusError: Error, Equatable {
    case invalidConfiguration
    case invalidTimestamp
    case nativeStatus(UInt32)
}
