import Foundation

/// Moves portable encoding and native bus publication away from UI callbacks.
/// A single worker preserves source event arrival order. Overflow is explicit.
public final class SpatialIngressPublisher: @unchecked Sendable {
    public struct Counters: Sendable, Equatable {
        public var queued: UInt64 = 0
        public var rejected: UInt64 = 0
        public var published: UInt64 = 0
        public var nativeRejected: UInt64 = 0
    }

    private enum Item: Sendable {
        case head(HeadSample, simulated: Bool)
        case telemetry(AircraftSnapshot)
    }
    private let continuation: AsyncStream<Item>.Continuation
    private let worker: Task<Void, Never>
    private let metrics = IngressMetrics()

    public init(bus: SpatialBus, capacity: Int = 256) {
        var owner: AsyncStream<Item>.Continuation?
        let stream = AsyncStream<Item>(bufferingPolicy: .bufferingOldest(max(1, min(4096, capacity)))) {
            owner = $0
        }
        continuation = owner!
        let metrics = self.metrics
        worker = Task.detached(priority: .utility) {
            for await event in stream {
                let accepted: Bool
                switch event {
                case .head(let sample, let simulated):
                    accepted = bus.publish(head: sample, simulated: simulated)
                case .telemetry(let sample):
                    accepted = bus.publish(aircraft: sample)
                }
                metrics.published(accepted)
            }
        }
    }

    @discardableResult
    public func send(head: HeadSample, simulated: Bool = false) -> Bool {
        accept(continuation.yield(.head(head, simulated: simulated)))
    }

    @discardableResult
    public func send(telemetry: AircraftSnapshot) -> Bool {
        accept(continuation.yield(.telemetry(telemetry)))
    }

    private func accept(_ result: AsyncStream<Item>.Continuation.YieldResult) -> Bool {
        if case .enqueued = result {
            metrics.queued(true)
            return true
        }
        metrics.queued(false)
        return false
    }

    public func snapshot() -> Counters { metrics.snapshot() }

    public func finish() async {
        continuation.finish()
        await worker.value
    }

    deinit {
        continuation.finish()
        worker.cancel()
    }
}

private final class IngressMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var counters = SpatialIngressPublisher.Counters()

    func queued(_ accepted: Bool) {
        lock.lock()
        if accepted { counters.queued &+= 1 } else { counters.rejected &+= 1 }
        lock.unlock()
    }

    func published(_ accepted: Bool) {
        lock.lock()
        if accepted { counters.published &+= 1 } else { counters.nativeRejected &+= 1 }
        lock.unlock()
    }

    func snapshot() -> SpatialIngressPublisher.Counters {
        lock.lock()
        let result = counters
        lock.unlock()
        return result
    }
}
