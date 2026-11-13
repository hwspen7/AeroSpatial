import AeroSpatialNative
import Foundation

/// Zero-allocation native histogram on the hot path. Deinit requires quiesced callers.
public final class NativeRuntimeMetrics: @unchecked Sendable {
    private let native: OpaquePointer
    public init?(deadlineNanoseconds: UInt64) {
        guard let metrics = as_runtime_metrics_create(deadlineNanoseconds) else { return nil }
        native = metrics
    }
    deinit { as_runtime_metrics_destroy(native) }
    @discardableResult
    public func record(_ durationNanoseconds: UInt64) -> Bool {
        as_runtime_metrics_record(native, durationNanoseconds) != 0
    }
    public func report() -> ASRuntimeReport? {
        var report = ASRuntimeReport()
        return as_runtime_metrics_report(native, &report) != 0 ? report : nil
    }
    /// Reset only when there are no concurrent writers or readers.
    public func resetWhenIdle() { as_runtime_metrics_reset(native) }
}
