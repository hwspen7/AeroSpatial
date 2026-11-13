import Foundation

public extension SpatialBus {
    /// Convert only finite nonnegative host-uptime values. Never accept Unix wall time.
    static func uptimeNanoseconds(_ uptime: TimeInterval) -> UInt64? {
        guard uptime.isFinite, uptime >= 0, uptime < Double(UInt64.max) / 1e9 else { return nil }
        return UInt64(uptime * 1e9)
    }

    @discardableResult
    func publish(head: HeadSample, simulated: Bool = false) -> Bool {
        guard head.pose.isFinite, let timestamp = Self.uptimeNanoseconds(head.uptime),
              let bytes = try? JSONEncoder().encode(head) else { return false }
        let quality: SpatialQuality = simulated ? [.valid, .simulated] : [.valid]
        return publish(stream: .head, timestampNanoseconds: timestamp,
                       quality: quality, payload: bytes) == 0
    }

    @discardableResult
    func publish(aircraft: AircraftSnapshot) -> Bool {
        guard aircraft.isValid, let timestamp = Self.uptimeNanoseconds(aircraft.uptime),
              let bytes = try? JSONEncoder().encode(aircraft) else { return false }
        let quality: SpatialQuality = aircraft.source == .simulator ? [.valid, .simulated] : [.valid]
        return publish(stream: .telemetry, timestampNanoseconds: timestamp,
                       quality: quality, payload: bytes) == 0
    }

    /// Video is encoded bytes (such as H.264 NAL data), never an implicit raw pixel buffer.
    /// Ownership is copied once at the C boundary; native subscriber fan-out is shared.
    @discardableResult
    func publishEncodedVideo(_ bytes: Data, timestampNanoseconds: UInt64,
                             clockDomain: UInt32, codec: UInt32, traceID: UInt64 = 0,
                             quality: SpatialQuality = [.valid]) -> Bool {
        publish(stream: .video, timestampNanoseconds: timestampNanoseconds,
                clockDomain: clockDomain, kind: codec, quality: quality,
                traceID: traceID, payload: bytes) == 0
    }

    @discardableResult
    func publishPerception(_ bytes: Data, timestampNanoseconds: UInt64,
                           clockDomain: UInt32, modelID: UInt32,
                           quality: SpatialQuality = [.valid]) -> Bool {
        publish(stream: .perception, timestampNanoseconds: timestampNanoseconds,
                clockDomain: clockDomain, kind: modelID, quality: quality,
                payload: bytes) == 0
    }
}
