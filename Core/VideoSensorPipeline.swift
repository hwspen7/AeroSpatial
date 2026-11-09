import Foundation

/// Metadata-only fusion of independently timestamped streams. The video bytes stay
/// in SpatialBus, not in this timeline. No implicit clock-domain conversions.
public actor VideoSensorPipeline {
    private var timeline: MultimodalTimeline
    private var lastByStream: [SpatialStream: UInt64] = [:]
    public private(set) var rejected: UInt64 = 0
    public private(set) var accepted: UInt64 = 0

    public init(capacityPerStream: Int = 128) {
        timeline = MultimodalTimeline(capacityPerStream: capacityPerStream)
    }

    @discardableResult
    public func observe(_ event: SpatialEvent, alignedNanoseconds: UInt64,
                        uncertaintyNanoseconds: UInt64) -> Bool {
        guard event.stream == .video || event.stream == .head || event.stream == .telemetry,
              event.sequence > (lastByStream[event.stream] ?? 0),
              let point = TimelinePoint(event: event, alignedNanoseconds: alignedNanoseconds,
                                        uncertaintyNanoseconds: uncertaintyNanoseconds),
              timeline.append(point) else {
            rejected &+= 1
            return false
        }
        lastByStream[event.stream] = event.sequence
        accepted &+= 1
        return true
    }

    public func bundle(at timestampNanoseconds: UInt64,
                       maximumSkewNanoseconds: UInt64 = 50_000_000,
                       maximumUncertaintyNanoseconds: UInt64 = 20_000_000) -> FrameBundle? {
        FrameBundle.resolve(in: timeline, at: timestampNanoseconds,
                            maximumSkewNanoseconds: maximumSkewNanoseconds,
                            maximumClockUncertaintyNanoseconds: maximumUncertaintyNanoseconds)
    }

    public func reset() {
        timeline = MultimodalTimeline(capacityPerStream: timeline.capacityPerStream)
        lastByStream.removeAll()
        rejected = 0
        accepted = 0
    }
}
