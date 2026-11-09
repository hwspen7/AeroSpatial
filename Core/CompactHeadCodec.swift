import AeroSpatialNative
import Foundation

/// Fixed-size native record for high-rate head telemetry, independently CRC checked.
/// This is opt-in. Legacy JSON decoding remains supported for stored sessions.
public enum CompactHeadCodec {
    public static let messageKind = UInt32(AS_HEAD_WIRE_KIND)

    public static func encode(_ sample: HeadSample) -> Data? {
        guard sample.pose.isFinite, sample.uptime.isFinite else { return nil }
        var data = Data(count: Int(AS_HEAD_WIRE_BYTES))
        let packed = data.withUnsafeMutableBytes { buffer in
            as_head_wire_pack(sample.uptime, sample.pose.yaw, sample.pose.pitch,
                              sample.pose.roll, buffer.baseAddress, buffer.count)
        }
        return packed == 1 ? data : nil
    }

    public static func decode(_ data: Data) -> HeadSample? {
        var uptime: Double = 0
        var yaw: Double = 0
        var pitch: Double = 0
        var roll: Double = 0
        let valid = data.withUnsafeBytes { buffer in
            as_head_wire_unpack(buffer.baseAddress, buffer.count,
                                &uptime, &yaw, &pitch, &roll)
        }
        return valid == 1 ? HeadSample(uptime: uptime,
            pose: HeadPose(yaw: yaw, pitch: pitch, roll: roll)) : nil
    }
}

public extension SpatialBus {
    @discardableResult
    func publishCompact(head: HeadSample, simulated: Bool = false) -> Bool {
        guard let stamp = Self.uptimeNanoseconds(head.uptime),
              let payload = CompactHeadCodec.encode(head) else { return false }
        let quality: SpatialQuality = simulated ? [.valid, .simulated] : [.valid]
        return publish(stream: .head, timestampNanoseconds: stamp,
                       kind: CompactHeadCodec.messageKind,
                       quality: quality, payload: payload) == 0
    }
}
