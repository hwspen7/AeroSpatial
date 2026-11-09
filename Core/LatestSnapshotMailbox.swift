import Foundation

/// Bounded last-value mailbox for telemetry that is safe to coalesce for UI.
/// It does not replace the aircraft SDK's own safety/failsafe telemetry checks.
public final class LatestSnapshotMailbox<Value: Sendable>: @unchecked Sendable {
    private let mutex = NSLock()
    private var pending: Value?
    private var receivedCount: UInt64 = 0
    private var supersededCount: UInt64 = 0

    public init() {}

    public func offer(_ value: Value) {
        mutex.lock()
        if pending != nil { supersededCount &+= 1 }
        pending = value
        receivedCount &+= 1
        mutex.unlock()
    }

    public func takeLatest() -> Value? {
        mutex.lock()
        defer { mutex.unlock() }
        let value = pending
        pending = nil
        return value
    }

    public var counters: (received: UInt64, superseded: UInt64) {
        mutex.lock()
        defer { mutex.unlock() }
        return (receivedCount, supersededCount)
    }
}
