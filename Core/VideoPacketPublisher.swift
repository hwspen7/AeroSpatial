import Foundation

/// Bounded H.264 elementary-stream chunk ingress, not an access-unit decoder.
/// DJI SDK delivers arbitrary byte chunks, not necessarily complete video frames.
/// Callback receipt time is explicitly marked as an estimated capture timestamp.
public final class VideoPacketPublisher: @unchecked Sendable {
    /// Encoded unit kind = 0x200 | H.264 NAL type. This is not a frame codec ID.
    public static let h264NALKindBase: UInt32 = 0x200

    public struct Counters: Sendable, Equatable {
        public var queued: UInt64 = 0
        public var overwritten: UInt64 = 0
        public var rejected: UInt64 = 0
        public var forwarded: UInt64 = 0
        public var nativeRejected: UInt64 = 0
    }

    private struct Packet: Sendable {
        let data: Data
        let timestamp: UInt64
        let gap: Bool
        let serial: UInt64
    }

    private let lock = NSLock()
    private let continuation: AsyncStream<Packet>.Continuation
    private let worker: Task<Void, Never>
    private var closed = false
    private var lastReceived: UInt64 = 0
    private var pendingGap = true
    private var acceptedSerial: UInt64 = 0
    private var counts = Counters()

    public init(bus: SpatialBus, capacity: Int = 8) {
        var producer: AsyncStream<Packet>.Continuation?
        let packets = AsyncStream<Packet>(
            bufferingPolicy: .bufferingNewest(max(1, min(64, capacity)))
        ) { producer = $0 }
        let continuation = producer!
        self.continuation = continuation
        // Native publication and payload copying never run on the app's MainActor.
        // The worker retains only the bus and a counter updater, not the adapter.
        let metrics = VideoPacketMetrics()
        self.metrics = metrics
        worker = Task.detached(priority: .utility) {
            guard let assembler = H264UnitAssembler() else { return }
            var lastSerial: UInt64 = 0
            var previousFailure = false
            for await packet in packets {
                // A gap may arise from SDK disconnect, source errors or queue eviction.
                // Never decode across an unobserved fragment discontinuity.
                let discontinuity = packet.gap || previousFailure ||
                    (lastSerial > 0 && packet.serial != lastSerial + 1)
                lastSerial = packet.serial
                if discontinuity { assembler.reset() }
                previousFailure = false
                do {
                    let units = try assembler.accept(packet.data)
                    for unit in units {
                        var quality: SpatialQuality = [.valid, .clockEstimated, .lowConfidence]
                        if discontinuity { quality.insert(.upstreamGap) }
                        let status = bus.publish(stream: .video,
                                                 timestampNanoseconds: packet.timestamp,
                                                 clockDomain: 1,
                                                 kind: Self.h264NALKindBase | UInt32(unit.type),
                                                 quality: quality, payload: unit.bytes)
                        metrics.record(nativeAccepted: status == 0)
                        if status != 0 { previousFailure = true }
                    }
                } catch {
                    assembler.reset()
                    previousFailure = true
                    metrics.record(nativeAccepted: false)
                }
            }
        }
    }

    private let metrics: VideoPacketMetrics

    /// May be called from a DJI SDK callback on a non-main serial queue.
    @discardableResult
    public func receive(_ bytes: Data, receivedAtNanoseconds timestamp: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, timestamp > 0, timestamp >= lastReceived,
              !bytes.isEmpty, bytes.count <= 2 * 1024 * 1024 else {
            counts.rejected &+= 1
            pendingGap = true
            return false
        }
        let packet = Packet(data: bytes, timestamp: timestamp, gap: pendingGap,
                            serial: acceptedSerial &+ 1)
        switch continuation.yield(packet) {
        case .enqueued:
            counts.queued &+= 1
            acceptedSerial &+= 1
            pendingGap = false
        case .dropped:
            // An older chunk was evicted. The following accepted chunk must
            // signal discontinuity because the H.264 decoder needs resync.
            counts.queued &+= 1
            acceptedSerial &+= 1
            counts.overwritten &+= 1
            pendingGap = true
        case .terminated:
            counts.rejected &+= 1
            pendingGap = true
            return false
        @unknown default:
            counts.rejected &+= 1
            pendingGap = true
            return false
        }
        lastReceived = timestamp
        return true
    }

    /// Called on physical feed reconnect, disconnection, or stream restart.
    public func markDiscontinuity() {
        lock.lock()
        pendingGap = true
        lock.unlock()
    }

    public func snapshot() -> Counters {
        lock.lock()
        var result = counts
        lock.unlock()
        let native = metrics.snapshot()
        result.forwarded = native.forwarded
        result.nativeRejected = native.rejected
        return result
    }

    /// Finishes the producer and waits until the native bus worker drains.
    public func finish() async {
        close()
        await worker.value
    }

    public func close() {
        lock.lock()
        if !closed { closed = true; continuation.finish() }
        lock.unlock()
    }

    deinit { close() }
}

/// Lock-protected metrics are updated by the detached worker only.
private final class VideoPacketMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var forwarded: UInt64 = 0
    private var rejected: UInt64 = 0

    func record(nativeAccepted: Bool) {
        lock.lock()
        if nativeAccepted { forwarded &+= 1 } else { rejected &+= 1 }
        lock.unlock()
    }

    func snapshot() -> (forwarded: UInt64, rejected: UInt64) {
        lock.lock()
        let result = (forwarded, rejected)
        lock.unlock()
        return result
    }
}
