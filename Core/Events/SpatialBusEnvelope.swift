import Foundation

/// Portable diagnostics envelope. Avoid including raw video frames by default.
public struct SpatialBusEnvelope: Codable, Equatable, Sendable {
    public let stream: UInt32
    public let timestampNs: UInt64
    public let sequence: UInt64
    public let clockDomain: UInt32
    public let kind: UInt32
    public let traceId: UInt64
    public let quality: UInt32
    public let missed: UInt64
    public let payloadBytes: Int
    public let payloadBase64: String?

    public init(_ event: SpatialEvent, includePayload: Bool = false) {
        stream = event.stream.rawValue
        timestampNs = event.timestampNanoseconds
        sequence = event.sequence
        clockDomain = event.clockDomain
        kind = event.kind
        traceId = event.traceID
        quality = event.quality.rawValue
        missed = event.missed
        payloadBytes = event.payload.count
        // An explicit opt-in may include small opaque payloads, never video content.
        payloadBase64 = includePayload && event.stream != .video && event.payload.count <= 8192
            ? event.payload.base64EncodedString() : nil
    }
}
