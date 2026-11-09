import AeroSpatialNative
import Foundation

/// SPSC input for headphone callbacks. Push never allocates native storage.
/// UI-only coalescing is explicit; flight-command freshness is validated elsewhere.
public final class RealtimeHeadIngress: @unchecked Sendable {
    private let handle: OpaquePointer

    public init?(capacity: UInt32 = 256) {
        guard let native = as_rt_head_create(capacity) else { return nil }
        handle = native
    }

    deinit { as_rt_head_destroy(handle) }

    @discardableResult
    public func offer(_ sample: HeadSample, receivedAt: Double? = nil) -> Bool {
        let raw = ASRealtimeHeadSample(uptime_seconds: sample.uptime,
                                       yaw_degrees: sample.pose.yaw,
                                       pitch_degrees: sample.pose.pitch,
                                       roll_degrees: sample.pose.roll,
                                       received_host_seconds: receivedAt ?? sample.uptime)
        return as_rt_head_push(handle, raw) == ASRT_OK
    }

    public func takeLatestObservation() -> RealtimeHeadObservation? {
        var sample = ASRealtimeHeadSample()
        guard as_rt_head_pop_latest(handle, &sample) == ASRT_OK else { return nil }
        let head = HeadSample(uptime: sample.uptime_seconds,
                              pose: HeadPose(yaw: sample.yaw_degrees,
                                             pitch: sample.pitch_degrees,
                                             roll: sample.roll_degrees))
        return RealtimeHeadObservation(sample: head, receivedHostSeconds: sample.received_host_seconds)
    }

    public func takeLatest() -> HeadSample? { takeLatestObservation()?.sample }

    public var counters: RealtimeIngressCounters? {
        var stats = ASRealtimeQueueStats()
        guard as_rt_head_stats(handle, &stats) == ASRT_OK else { return nil }
        return RealtimeIngressCounters(accepted: stats.accepted, full: stats.rejected_full,
                                       invalid: stats.rejected_invalid, consumed: stats.consumed,
                                       coalesced: stats.coalesced)
    }
}

public struct RealtimeHeadObservation: Sendable, Equatable {
    public let sample: HeadSample
    public let receivedHostSeconds: Double
}

public struct RealtimeIngressCounters: Sendable, Equatable {
    public let accepted: UInt64
    public let full: UInt64
    public let invalid: UInt64
    public let consumed: UInt64
    public let coalesced: UInt64
}
