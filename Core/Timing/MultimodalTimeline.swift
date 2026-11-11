import Foundation

/// Metadata-only normalized timestamp; the caller must explicitly translate clock domains.
/// Retaining a video frame or other large payload here would defeat the bus memory bounds.
public struct TimelinePoint: Sendable, Equatable {
    public let stream: SpatialStream
    public let sequence: UInt64
    public let alignedNanoseconds: UInt64
    public let uncertaintyNanoseconds: UInt64
    public let sourceClockDomain: UInt32
    public let quality: SpatialQuality
    public let traceID: UInt64

    public init?(event: SpatialEvent, alignedNanoseconds: UInt64,
                 uncertaintyNanoseconds: UInt64) {
        guard event.sequence > 0, event.clockDomain > 0,
              event.quality.contains(.valid) else { return nil }
        self.stream = event.stream
        self.sequence = event.sequence
        self.alignedNanoseconds = alignedNanoseconds
        self.uncertaintyNanoseconds = uncertaintyNanoseconds
        self.sourceClockDomain = event.clockDomain
        self.quality = event.quality
        self.traceID = event.traceID
    }
}

public struct TimelineAlignment: Sendable, Equatable {
    public let referenceNanoseconds: UInt64
    public let observations: [SpatialStream: TimelinePoint]
    public let maximumObservedSkewNanoseconds: UInt64
}

/// Bounded, metadata-only nearest-neighbor alignment on an explicitly unified clock.
/// No interpolation and no control output. A source clock domain is never silently remapped.
public struct MultimodalTimeline: Sendable {
    public let capacityPerStream: Int
    private var buffers: [SpatialStream: TimestampRing<TimelinePoint>] = [:]
    public private(set) var rejected: UInt64 = 0

    public init(capacityPerStream: Int = 128) {
        self.capacityPerStream = max(2, min(4096, capacityPerStream))
    }

    @discardableResult
    public mutating func append(_ point: TimelinePoint) -> Bool {
        if let previous = buffers[point.stream]?.latest,
           (point.sequence <= previous.sequence || point.alignedNanoseconds < previous.alignedNanoseconds) {
            rejected += 1
            return false
        }
        if buffers[point.stream] == nil {
            buffers[point.stream] = TimestampRing(capacity: capacityPerStream)
        }
        buffers[point.stream]!.append(point)
        return true
    }

    public func aligned(at reference: UInt64, requiring streams: [SpatialStream],
                        maximumSkewNanoseconds: UInt64,
                        maximumClockUncertaintyNanoseconds: UInt64) -> TimelineAlignment? {
        guard !streams.isEmpty, Set(streams).count == streams.count else { return nil }
        var result: [SpatialStream: TimelinePoint] = [:]
        var observedMaximum: UInt64 = 0
        for stream in streams {
            guard let buffer = buffers[stream], buffer.count > 0,
                  let nearest = Self.nearest(in: buffer, at: reference) else { return nil }
            let skew = Self.distance(nearest.alignedNanoseconds, reference)
            guard nearest.quality.contains(.valid),
                  !nearest.quality.contains(.stale),
                  nearest.uncertaintyNanoseconds <= maximumClockUncertaintyNanoseconds,
                  skew <= maximumSkewNanoseconds,
                  nearest.uncertaintyNanoseconds <= maximumSkewNanoseconds - skew else {
                return nil
            }
            result[stream] = nearest
            observedMaximum = max(observedMaximum, skew)
        }
        return TimelineAlignment(referenceNanoseconds: reference, observations: result,
                                 maximumObservedSkewNanoseconds: observedMaximum)
    }

    private static func nearest(in buffer: TimestampRing<TimelinePoint>, at time: UInt64)
        -> TimelinePoint? {
        var lo = 0
        var hi = buffer.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if buffer[mid].alignedNanoseconds < time { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return buffer[0] }
        if lo == buffer.count { return buffer[lo - 1] }
        let before = buffer[lo - 1]
        let after = buffer[lo]
        return distance(before.alignedNanoseconds, time) <= distance(after.alignedNanoseconds, time)
            ? before : after
    }

    private static func distance(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }
}
