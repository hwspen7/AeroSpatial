import Foundation

/// Moves portable encoding and native bus publication away from UI callbacks.
/// A single worker preserves source event arrival order. Overflow is explicit.
public final class SpatialIngressPublisher: @unchecked Sendable {
    private enum Item: Sendable {
        case head(HeadSample, simulated: Bool)
        case telemetry(AircraftSnapshot)
    }
    private let continuation: AsyncStream<Item>.Continuation
    private let worker: Task<Void, Never>

    public init(bus: SpatialBus, capacity: Int = 256) {
        var owner: AsyncStream<Item>.Continuation?
        let stream = AsyncStream<Item>(bufferingPolicy: .bufferingOldest(max(1, min(4096, capacity)))) {
            owner = $0
        }
        continuation = owner!
        worker = Task.detached(priority: .utility) {
            for await event in stream {
                switch event {
                case .head(let sample, let simulated):
                    _ = bus.publish(head: sample, simulated: simulated)
                case .telemetry(let sample):
                    _ = bus.publish(aircraft: sample)
                }
            }
        }
    }

    @discardableResult
    public func send(head: HeadSample, simulated: Bool = false) -> Bool {
        if case .enqueued = continuation.yield(.head(head, simulated: simulated)) { return true }
        return false
    }

    @discardableResult
    public func send(telemetry: AircraftSnapshot) -> Bool {
        if case .enqueued = continuation.yield(.telemetry(telemetry)) { return true }
        return false
    }

    deinit {
        continuation.finish()
        worker.cancel()
    }
}
