import AeroSpatialNative
import Foundation

/// Thread-safe native transport. No network, no persistent buffers, no flight commands.
public final class SpatialBus: @unchecked Sendable {
    private let native: OpaquePointer

    public init() throws {
        var configuration = ASBusConfig(max_topics: 5, max_subscribers_per_topic: 16)
        guard let created = as_bus_create(&configuration) else {
            throw SpatialBusError.invalidConfiguration
        }
        native = created
        let topics: [(SpatialStream, UInt32, UInt32, UInt32)] = [
            (.head, 256, 512, UInt32(ASBUS_OVERWRITE_OLDEST.rawValue)),
            (.telemetry, 256, 4096, UInt32(ASBUS_OVERWRITE_OLDEST.rawValue)),
            (.video, 8, 2 * 1024 * 1024, UInt32(ASBUS_OVERWRITE_OLDEST.rawValue)),
            (.perception, 128, 8192, UInt32(ASBUS_OVERWRITE_OLDEST.rawValue)),
            (.diagnostic, 128, 4096, UInt32(ASBUS_REJECT_NEWEST.rawValue))
        ]
        for (stream, capacity, maxPayload, policy) in topics {
            let options = ASBusTopicConfig(stream_id: stream.rawValue, capacity: capacity,
                                           max_payload_bytes: maxPayload, overflow: policy)
            if as_bus_add_topic(native, options) != ASBUS_OK {
                as_bus_destroy(native)
                throw SpatialBusError.invalidConfiguration
            }
        }
    }

    deinit { as_bus_destroy(native) }

    @discardableResult
    public func publish(stream: SpatialStream, timestampNanoseconds: UInt64,
                        clockDomain: UInt32 = 1, kind: UInt32 = 0,
                        quality: SpatialQuality = [.valid], traceID: UInt64 = 0,
                        payload: Data) -> UInt32 {
        let header = ASBusHeader(timestamp_ns: timestampNanoseconds, sequence: 0,
                                 trace_id: traceID, stream_id: stream.rawValue,
                                 clock_domain: clockDomain, quality_flags: quality.rawValue, kind: kind)
        let status = payload.withUnsafeBytes { bytes in
            as_bus_publish(native, header, bytes.baseAddress, bytes.count)
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
        return SpatialStreamStats(published: stats.published,
                                  overwritten: stats.overwritten,
                                  rejected: stats.rejected, invalid: stats.invalid,
                                  retainedBytes: stats.retained_bytes,
                                  highWaterBytes: stats.high_water_bytes,
                                  retainedEvents: stats.retained_events,
                                  subscribers: stats.active_subscribers)
    }
}

/// One outstanding native lease is allowed, copied into Swift Data and released before return.
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
        if status == ASBUS_EMPTY { return nil }
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
