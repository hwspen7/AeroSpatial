import Foundation

/// Encoded elementary-stream frames only. No decoder or DJI SDK dependency.
public struct EncodedFrame: Sendable {
    public enum Codec: UInt32, Sendable { case h264 = 1, h265 = 2, mjpeg = 3 }
    public let bytes: Data
    public let codec: Codec
    public let timestampNanoseconds: UInt64
    public let clockDomain: UInt32
    public let traceID: UInt64
    public let estimatedClock: Bool

    public init?(bytes: Data, codec: Codec, timestampNanoseconds: UInt64,
                 clockDomain: UInt32, traceID: UInt64, estimatedClock: Bool = false) {
        guard !bytes.isEmpty, bytes.count <= 2 * 1024 * 1024, clockDomain != 0 else { return nil }
        self.bytes = bytes
        self.codec = codec
        self.timestampNanoseconds = timestampNanoseconds
        self.clockDomain = clockDomain
        self.traceID = traceID
        self.estimatedClock = estimatedClock
    }
}

/// Tracks source discontinuities and publishes only validated, bounded video frames.
/// The caller supplies capture timestamps; receipt time is not silently substituted.
public struct VideoIngress {
    private var domain: UInt32?
    private var lastTimestamp: UInt64?
    public private(set) var accepted: UInt64 = 0
    public private(set) var rejected: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func publish(_ frame: EncodedFrame, to bus: SpatialBus) -> Bool {
        if domain != nil && domain != frame.clockDomain ||
           lastTimestamp.map({ frame.timestampNanoseconds < $0 }) == true {
            rejected += 1
            return false
        }
        let quality: SpatialQuality = frame.estimatedClock ? [.valid, .clockEstimated] : [.valid]
        guard bus.publishEncodedVideo(frame.bytes, timestampNanoseconds: frame.timestampNanoseconds,
                                      clockDomain: frame.clockDomain, codec: frame.codec.rawValue,
                                      traceID: frame.traceID, quality: quality) else {
            rejected += 1
            return false
        }
        domain = frame.clockDomain
        lastTimestamp = frame.timestampNanoseconds
        accepted += 1
        return true
    }
}
