import Foundation

/// A fixed-size FIFO with O(1) insertion and eviction. Actor confinement is external.
private struct PendingRing {
    private var slots: [SpatialEvent?]
    private var head = 0
    private(set) var count = 0
    init(capacity: Int) { slots = Array(repeating: nil, count: capacity) }
    var capacity: Int { slots.count }
    mutating func append(_ event: SpatialEvent, replacingOldest: Bool) -> Bool {
        let full = count == capacity
        if full && !replacingOldest { return false }
        if full {
            slots[head] = nil
            head = (head + 1) % capacity
            count -= 1
        }
        slots[(head + count) % capacity] = event
        count += 1
        return true
    }
    mutating func pop() -> SpatialEvent? {
        guard count > 0 else { return nil }
        let event = slots[head]
        slots[head] = nil
        head = (head + 1) % capacity
        count -= 1
        return event
    }
}

/// Bounded observation-only mailbox. Scheduling, aircraft command authorization and
/// recording durability are deliberately separate concerns.
public actor RealtimeIngress {
    public enum Lane: Sendable { case essential, optional }
    public enum Admission: Equatable, Sendable { case accepted, overwritten, rejected }
    public struct Counters: Equatable, Sendable {
        public var accepted: UInt64 = 0
        public var overwritten: UInt64 = 0
        public var rejected: UInt64 = 0
        public var drained: UInt64 = 0
    }

    private var essential: PendingRing
    private var optional: PendingRing
    private var statistics = Counters()

    public init(essentialLimit: Int = 256, optionalLimit: Int = 32) {
        essential = PendingRing(capacity: max(1, min(4096, essentialLimit)))
        optional = PendingRing(capacity: max(1, min(4096, optionalLimit)))
    }

    /// Essential observations are reject-on-full; never silently drop a head/telemetry sample.
    /// Optional work is overwrite-oldest. Commands do not flow through this API.
    @discardableResult
    public func offer(_ event: SpatialEvent, lane: Lane) -> Admission {
        switch lane {
        case .essential:
            guard essential.append(event, replacingOldest: false) else {
                statistics.rejected &+= 1
                return .rejected
            }
            statistics.accepted &+= 1
            return .accepted
        case .optional:
            let replaced = optional.count == optional.capacity
            _ = optional.append(event, replacingOldest: true)
            if replaced { statistics.overwritten &+= 1 }
            statistics.accepted &+= 1
            return replaced ? .overwritten : .accepted
        }
    }

    /// Essential observations are drained first, under an explicit work budget.
    public func take(maximum: Int = 32) -> [SpatialEvent] {
        let limit = max(1, min(4096, maximum))
        var result: [SpatialEvent] = []
        result.reserveCapacity(min(limit, essential.count + optional.count))
        while result.count < limit {
            guard let next = essential.pop() ?? optional.pop() else { break }
            result.append(next)
        }
        statistics.drained &+= UInt64(result.count)
        return result
    }

    public func snapshot() -> (pendingEssential: Int, pendingOptional: Int, counters: Counters) {
        (essential.count, optional.count, statistics)
    }
}
