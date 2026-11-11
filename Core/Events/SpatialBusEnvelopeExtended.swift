import Foundation

/// Explicitly versioned metadata export. No raw camera buffers or audio are embedded.
public struct SpatialBusEnvelopeExtended: Codable, Sendable, Equatable {
    public let version: Int
    public let stream: UInt32
    public let timestampNs: UInt64
    public let sequence: UInt64
    public let clockDomain: UInt32
    public let kind: UInt32
    public let traceId: UInt64
    public let quality: UInt32
    public let missed: UInt64
    public let payloadBytes: Int
    public let upstreamMissing: UInt64
    public let sampled: UInt64
    public let rejected: UInt64
    public let alignedNs: UInt64?
    public let uncertaintyNs: UInt64?

    public init(_ event: SpatialEvent, upstreamMissing: UInt64 = 0,
                sampled: UInt64 = 0, rejected: UInt64 = 0,
                alignedNs: UInt64? = nil, uncertaintyNs: UInt64? = nil) {
        version = 2
        stream = event.stream.rawValue
        timestampNs = event.timestampNanoseconds
        sequence = event.sequence
        clockDomain = event.clockDomain
        kind = event.kind
        traceId = event.traceID
        quality = event.quality.rawValue
        missed = event.missed
        payloadBytes = event.payload.count
        self.upstreamMissing = upstreamMissing
        self.sampled = sampled
        self.rejected = rejected
        self.alignedNs = alignedNs
        self.uncertaintyNs = alignedNs == nil ? nil : uncertaintyNs
    }
}
