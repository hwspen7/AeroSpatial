import AeroSpatialNative
import Foundation

/// Thread-safe in-process event transport. Not a flight-command channel.
public final class SpatialBus: @unchecked Sendable {
    private let native: OpaquePointer
    private let publishers: [SpatialStream: OpaquePointer]

    public init(payloadBudgetBytes: UInt64 = 64 * 1024 * 1024) throws {
        var configuration = ASBusConfig(max_topics: 5, max_subscribers_per_topic: 16)
        guard let created = as_bus_create(&configuration) else {
            throw SpatialBusError.invalidConfiguration
        }
        let topics: [(SpatialStream, UInt32, UInt32, UInt32)] = [
            (.head, 256, 512, UInt32(ASBUS_OVERWRITE_OLDEST.rawValue)),
            (.telemetry, 256, 4096, UInt32(ASBUS_OVERWRITE_OLDEST.rawValue)),
            (.video, 8, 2 * 1024 * 1024, UInt32(ASBUS_OVERWRITE_OLDEST.rawValue)),
            (.perception, 128, 8192, UInt32(ASBUS_OVERWRITE_OLDEST.rawValue)),
            (.diagnostic, 128, 4096, UInt32(ASBUS_REJECT_NEWEST.rawValue))
        ]
        var handles: [SpatialStream: OpaquePointer] = [:]
        guard as_bus_set_payload_budget(created, payloadBudgetBytes) == ASBUS_OK else {
            as_bus_destroy(created)
            throw SpatialBusError.invalidConfiguration
        }
        for (stream, capacity, maxPayload, policy) in topics {
            let options = ASBusTopicConfig(stream_id: stream.rawValue, capacity: capacity,
                                           max_payload_bytes: maxPayload, overflow: policy)
            guard as_bus_add_topic(created, options) == ASBUS_OK,
                  let publisher = as_bus_open_publisher(created, stream.rawValue) else {
                for handle in handles.values { as_bus_close_publisher(handle) }
                as_bus_destroy(created)
                throw SpatialBusError.invalidConfiguration
            }
            handles[stream] = publisher
        }
        native = created
        publishers = handles
    }

    deinit {
        for handle in publishers.values { as_bus_close_publisher(handle) }
        as_bus_destroy(native)
    }

    /// Uses cached native topic handles; does not re-lock the global topic index.
    @discardableResult
    public func publish(stream: SpatialStream, timestampNanoseconds: UInt64,
                        clockDomain: UInt32 = 1, kind: UInt32 = 0,
                        quality: SpatialQuality = [.valid], traceID: UInt64 = 0,
                        payload: Data) -> UInt32 {
        guard let publisher = publishers[stream] else { return UInt32(ASBUS_INVALID.rawValue) }
        let header = ASBusHeader(timestamp_ns: timestampNanoseconds, sequence: 0,
                                 trace_id: traceID, stream_id: stream.rawValue,
                                 clock_domain: clockDomain, quality_flags: quality.rawValue, kind: kind)
        let status = payload.withUnsafeBytes { bytes in
            as_bus_publish_fast(publisher, header, bytes.baseAddress, bytes.count)
        }
        return status.rawValue
    }

    public func subscribe(_ stream: SpatialStream, latest: Bool = true) -> SpatialSubscription? {
        guard let handle = as_bus_subscribe(native, stream.rawValue, latest ? 1 : 0) else { return nil }
        return SpatialSubscription(bus: self, stream: stream, handle: handle)
    }

    public func stats(for stream: SpatialStream) -> SpatialStreamStats? {
        var stats = ASBusTopicStats()
        guard as_bus_stats(native, stream.rawValue, &stats) == ASBUS_OK else { return nil }
        return SpatialStreamStats(published: stats.published, overwritten: stats.overwritten,
                                  rejected: stats.rejected, invalid: stats.invalid,
                                  retainedBytes: stats.retained_bytes,
                                  highWaterBytes: stats.high_water_bytes,
                                  retainedEvents: stats.retained_events,
                                  subscribers: stats.active_subscribers,
                                  budgetRejected: stats.budget_rejected)
    }

    public func memoryStats() -> SpatialMemoryStats? {
        var result = ASBusMemoryStats()
        guard as_bus_memory_stats(native, &result) == ASBUS_OK else { return nil }
        return SpatialMemoryStats(limitBytes: result.limit_bytes, liveBytes: result.live_bytes,
                                  highWaterBytes: result.high_water_bytes)
    }
}

/// A leased event is copied into Swift Data before releasing native storage.
public final class SpatialSubscription: @unchecked Sendable {
    private let bus: SpatialBus
    private let stream: SpatialStream
    private let handle: OpaquePointer

    fileprivate init(bus: SpatialBus, stream: SpatialStream, handle: OpaquePointer) {
        self.bus = bus
        self.stream = stream
        self.handle = handle
    }

    deinit { as_bus_unsubscribe(handle) }

    public func next() throws -> SpatialEvent? {
        var lease: OpaquePointer?
        var missed: UInt64 = 0
        let status = as_bus_acquire(handle, &lease, &missed)
        if status == ASBUS_EMPTY || status == ASBUS_CLOSED { return nil }
        guard status == ASBUS_OK, let lease else {
            throw SpatialBusError.nativeStatus(status.rawValue)
        }
        defer { as_bus_release(lease) }
        var size = 0
        var header = ASBusHeader()
        let pointer = as_bus_lease_data(lease, &size, &header)
        let payload = pointer.map { Data(bytes: $0, count: size) } ?? Data()
        return SpatialEvent(stream: stream, timestampNanoseconds: header.timestamp_ns,
                            sequence: header.sequence, clockDomain: header.clock_domain,
                            traceID: header.trace_id, kind: header.kind,
                            quality: SpatialQuality(rawValue: header.quality_flags),
                            missed: missed, payload: payload)
    }
}
