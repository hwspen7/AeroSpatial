import AeroSpatialNative
import Foundation

/// Shared immutable native byte storage. The initial insertion copies once.
/// Leases must not outlive their consumers; never escape borrowed pointers.
public final class NativeMemoryLease {
    private let handle: OpaquePointer
    fileprivate init(_ handle: OpaquePointer) { self.handle = handle }
    deinit { as_memory_lease_release(handle) }

    public func retained() -> NativeMemoryLease? {
        guard let pointer = as_memory_lease_retain(handle) else { return nil }
        return NativeMemoryLease(pointer)
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        var size = 0
        let address = as_memory_lease_data(handle, &size)
        return try body(UnsafeRawBufferPointer(start: address, count: size))
    }

    public var count: Int { withUnsafeBytes { $0.count } }
}

public final class NativeMemoryPool {
    private let handle: OpaquePointer

    public init?(maximumBytes: Int, maximumPayloadBytes: Int) {
        guard let created = as_memory_pool_create(maximumBytes, maximumPayloadBytes) else { return nil }
        handle = created
    }
    deinit { as_memory_pool_destroy(handle) }

    public func copy(_ data: Data) -> NativeMemoryLease? {
        guard let result = data.withUnsafeBytes({ raw in
            as_memory_pool_copy(handle, raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
        }) else { return nil }
        return NativeMemoryLease(result)
    }

    public var statistics: ASMemoryStats? {
        var result = ASMemoryStats()
        return as_memory_pool_stats(handle, &result) != 0 ? result : nil
    }
}
