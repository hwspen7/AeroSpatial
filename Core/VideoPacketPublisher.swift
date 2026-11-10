import Foundation

/// Native bounded H.264 chunk ingress with an optional C++ access-unit assembler.
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
        public var accessUnits: UInt64 = 0
        public var assemblyFailures: UInt64 = 0
        public var expired: UInt64 = 0
        public var queueP95Nanoseconds: UInt64 = 0
        public var processingP95Nanoseconds: UInt64 = 0
    }


    private let lock = NSLock()
    private let continuation: AsyncStream<Void>.Continuation
    private let nativeQueue: NativeWorkQueue?
    private let worker: Task<Void, Never>
    private var closed = false
    private var lastReceived: UInt64 = 0
    private var pendingGap = true
    private var acceptedSerial: UInt64 = 0
    private var counts = Counters()

    public init(bus: SpatialBus, capacity: Int = 8,
                onAccessUnit: (@Sendable (H264AccessUnit, UInt64, Bool) -> Void)? = nil,
                onDiscontinuity: (@Sendable () -> Void)? = nil) {
        let bounded = max(1, min(64, capacity))
        // Eight bytes contain the caller's original receipt clock. The queue
        // itself uses the host monotonic clock for deadline admission.
        let maximumPacket = 2 * 1024 * 1024 + 8
        let native = NativeWorkQueue(maximumEvents: bounded,
                                     maximumBytes: maximumPacket * bounded,
                                     maximumPayloadBytes: maximumPacket)
        nativeQueue = native
        var producer: AsyncStream<Void>.Continuation?
        let signals = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) {
            producer = $0
        }
        continuation = producer!
        let metrics = VideoPacketMetrics()
        self.metrics = metrics
        // Coalesced wakeups avoid one Swift task per fragment. The C++ queue
        // owns memory/deadline limits and publishes only on the worker.
        worker = Task.detached(priority: .utility) {
            guard let native, let assembler = H264UnitAssembler() else { return }
            let pictures = onAccessUnit == nil ? nil : H264AccessUnitAssembler()
            var lastSerial: UInt64 = 0
            var previousFailure = false
            var scratch: [UInt8] = []
            for await _ in signals {
                while let job = native.pop(at: DispatchTime.now().uptimeNanoseconds,
                                           reusing: &scratch) {
                    guard job.payload.count > 8 else { previousFailure = true; continue }
                    let stamp = job.payload.prefix(8).enumerated().reduce(UInt64(0)) {
                        $0 | (UInt64($1.element) << (UInt64($1.offset) * 8))
                    }
                    let chunk = Data(job.payload.dropFirst(8))
                    let operationStart = DispatchTime.now().uptimeNanoseconds
                    if operationStart >= job.receivedNanoseconds {
                        metrics.recordQueueWait(operationStart - job.receivedNanoseconds)
                    }
                    let discontinuity = job.kind != 0 || previousFailure ||
                        (lastSerial > 0 && job.traceID != lastSerial + 1)
                    lastSerial = job.traceID
                    if discontinuity {
                        onDiscontinuity?()
                        assembler.reset()
                        pictures?.reset()
                    }
                    previousFailure = false
                    do {
                        let units = try assembler.accept(chunk)
                        if let pictures {
                            do {
                                for picture in try pictures.accept(chunk) {
                                    onAccessUnit?(picture, stamp, discontinuity)
                                    metrics.recordAccessUnit()
                                }
                            } catch {
                                pictures.reset()
                                previousFailure = true
                                metrics.recordAssemblyFailure()
                            }
                        }
                        for unit in units {
                            var quality: SpatialQuality = [.valid, .clockEstimated, .lowConfidence]
                            if discontinuity { quality.insert(.upstreamGap) }
                            let status = bus.publish(stream: .video,
                                                     timestampNanoseconds: stamp,
                                                     clockDomain: 1,
                                                     kind: Self.h264NALKindBase | UInt32(unit.type),
                                                     quality: quality, payload: unit.bytes)
                            metrics.record(nativeAccepted: status == 0)
                            if status != 0 { previousFailure = true }
                        }
                    } catch {
                        assembler.reset()
                        pictures?.reset()
                        previousFailure = true
                        metrics.record(nativeAccepted: false)
                    }
                    let finished = DispatchTime.now().uptimeNanoseconds
                    if finished >= operationStart {
                        metrics.recordProcessing(finished - operationStart)
                    }
                }
            }
            native.close()
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
        guard let nativeQueue else {
            counts.rejected &+= 1
            pendingGap = true
            return false
        }
        let now = DispatchTime.now().uptimeNanoseconds
        var packed = Data(capacity: 8 + bytes.count)
        var little = timestamp.littleEndian
        withUnsafeBytes(of: &little) { packed.append(contentsOf: $0) }
        packed.append(bytes)
        let work = NativeWorkQueue.Work(
            traceID: acceptedSerial &+ 1, receivedNanoseconds: now,
            deadlineNanoseconds: now > UInt64.max - 500_000_000 ? UInt64.max : now + 500_000_000,
            kind: pendingGap ? 1 : 0, priority: .optional, payload: packed)
        guard nativeQueue.push(work, at: now) == .accepted else {
            counts.rejected &+= 1
            pendingGap = true
            return false
        }
        counts.queued &+= 1
        acceptedSerial &+= 1
        pendingGap = false
        _ = continuation.yield(())
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
        result.accessUnits = native.accessUnits
        result.assemblyFailures = native.assemblyFailures
        result.queueP95Nanoseconds = native.queueP95
        result.processingP95Nanoseconds = native.processingP95
        result.expired = nativeQueue?.report()?.expired ?? 0
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
    private var accessUnits: UInt64 = 0
    private var assemblyFailures: UInt64 = 0
    private let queueLatency = NativeRuntimeMetrics(deadlineNanoseconds: 100_000_000)
    private let processingLatency = NativeRuntimeMetrics(deadlineNanoseconds: 50_000_000)

    func record(nativeAccepted: Bool) {
        lock.lock()
        if nativeAccepted { forwarded &+= 1 } else { rejected &+= 1 }
        lock.unlock()
    }

    func recordAccessUnit() {
        lock.lock()
        accessUnits &+= 1
        lock.unlock()
    }
    func recordAssemblyFailure() {
        lock.lock()
        assemblyFailures &+= 1
        lock.unlock()
    }

    func recordQueueWait(_ nanoseconds: UInt64) {
        _ = queueLatency?.record(nanoseconds)
    }
    func recordProcessing(_ nanoseconds: UInt64) {
        _ = processingLatency?.record(nanoseconds)
    }

    func snapshot() -> (forwarded: UInt64, rejected: UInt64,
                        accessUnits: UInt64, assemblyFailures: UInt64,
                        queueP95: UInt64, processingP95: UInt64) {
        lock.lock()
        let result = (forwarded, rejected, accessUnits, assemblyFailures,
                      queueLatency?.report()?.p95_upper_ns ?? 0,
                      processingLatency?.report()?.p95_upper_ns ?? 0)
        lock.unlock()
        return result
    }
}
