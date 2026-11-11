import Foundation

/// Accepts pre-encoded frame buffers from any camera driver. A driver must provide
/// genuine capture timestamps or explicitly mark reception-time estimates.
public actor DeviceVideoPipeline {
    private let bus: SpatialBus
    private let timeline: VideoSensorPipeline
    private var ingress = VideoIngress()
    public private(set) var forwarded: UInt64 = 0
    public private(set) var rejected: UInt64 = 0

    public init(bus: SpatialBus, capacity: Int = 128) {
        self.bus = bus
        timeline = VideoSensorPipeline(capacityPerStream: capacity)
    }

    public func accept(_ frame: EncodedFrame) -> Bool {
        guard ingress.publish(frame, to: bus) else {
            rejected &+= 1
            return false
        }
        forwarded &+= 1
        return true
    }

    @discardableResult
    public func addTimelineMetadata(_ event: SpatialEvent,
                                    alignedNanoseconds: UInt64,
                                    uncertaintyNanoseconds: UInt64) async -> Bool {
        await timeline.observe(event, alignedNanoseconds: alignedNanoseconds,
                               uncertaintyNanoseconds: uncertaintyNanoseconds)
    }

    public func joined(at nanoseconds: UInt64, tolerance: UInt64 = 50_000_000,
                       uncertaintyLimit: UInt64 = 20_000_000) async -> FrameBundle? {
        await timeline.bundle(at: nanoseconds, maximumSkewNanoseconds: tolerance,
                              maximumUncertaintyNanoseconds: uncertaintyLimit)
    }
}
