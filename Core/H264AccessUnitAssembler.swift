import AeroSpatialNative
import Foundation

/// A complete H.264 encoded picture in AVCC layout, not decoded pixels.
/// Parameter sets are copied from native state and belong to this access unit.
public struct H264AccessUnit: Sendable, Equatable {
    public let avcc: Data
    public let sps: Data
    public let pps: Data
    public let ordinal: UInt64
    public let isKeyframe: Bool
}

/// Single-worker streaming assembler. Input chunks may end within a NAL start code.
/// Call reset() on source discontinuity; never infer that a received NAL is a frame.
public final class H264AccessUnitAssembler {
    public enum Failure: Error { case invalidData, resourceLimit }
    private let native: OpaquePointer
    private var collected: [H264AccessUnit] = []
    private var collectedNALs: [H264Unit] = []

    public init?(maximumNALBytes: Int = 2 * 1024 * 1024,
                 maximumAccessUnitBytes: Int = 8 * 1024 * 1024) {
        guard maximumNALBytes > 0, maximumAccessUnitBytes > 0,
              let ptr = as_h264_access_create(maximumNALBytes, maximumAccessUnitBytes) else {
            return nil
        }
        native = ptr
    }

    deinit { as_h264_access_destroy(native) }

    private static let callback: @convention(c)
        (UnsafeMutableRawPointer?, UnsafePointer<ASH264AccessUnit>?) -> Void = { context, packet in
        guard let context, let packet else { return }
        let owner = Unmanaged<H264AccessUnitAssembler>.fromOpaque(context).takeUnretainedValue()
        let entry = packet.pointee
        guard let avcc = entry.avcc_bytes, let sps = entry.sps_bytes, let pps = entry.pps_bytes else { return }
        owner.collected.append(H264AccessUnit(
            avcc: Data(bytes: avcc, count: entry.avcc_size),
            sps: Data(bytes: sps, count: entry.sps_size),
            pps: Data(bytes: pps, count: entry.pps_size),
            ordinal: entry.ordinal, isKeyframe: entry.keyframe != 0))
    }

    private static let nalCallback: @convention(c)
        (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int, UInt8) -> Void = { context, source, count, type in
        guard let context, let source else { return }
        let owner = Unmanaged<H264AccessUnitAssembler>.fromOpaque(context).takeUnretainedValue()
        owner.collectedNALs.append(H264Unit(type: type, bytes: Data(bytes: source, count: count)))
    }

    public func reset() {
        as_h264_access_reset(native)
        collected.removeAll(keepingCapacity: true)
        collectedNALs.removeAll(keepingCapacity: true)
    }

    public func accept(_ chunk: Data) throws -> [H264AccessUnit] {
        collected.removeAll(keepingCapacity: true)
        let result = chunk.withUnsafeBytes { bytes in
            as_h264_access_feed(native, bytes.bindMemory(to: UInt8.self).baseAddress,
                                chunk.count, Self.callback, Unmanaged.passUnretained(self).toOpaque())
        }
        switch result {
        case ASH264_OK: return collected
        case ASH264_TOO_LARGE: throw Failure.resourceLimit
        default: throw Failure.invalidData
        }
    }

    /// Processes caller-borrowed bytes. Source memory must remain valid until return.
    public func acceptWithNALs(_ raw: UnsafeRawBufferPointer) throws
        -> (units: [H264Unit], pictures: [H264AccessUnit]) {
        collected.removeAll(keepingCapacity: true)
        collectedNALs.removeAll(keepingCapacity: true)
        let status = as_h264_access_feed_dual(native,
            raw.bindMemory(to: UInt8.self).baseAddress, raw.count,
            Self.nalCallback, Self.callback, Unmanaged.passUnretained(self).toOpaque())
        switch status {
        case ASH264_OK: return (collectedNALs, collected)
        case ASH264_TOO_LARGE: throw Failure.resourceLimit
        default: throw Failure.invalidData
        }
    }

    /// Convenience path for clients holding Swift-owned bytes.
    public func acceptWithNALs(_ chunk: Data) throws
        -> (units: [H264Unit], pictures: [H264AccessUnit]) {
        try chunk.withUnsafeBytes { try acceptWithNALs($0) }
    }

    /// Emits a trailing AU only when the source is known to have ended cleanly.
    public func finish() throws -> [H264AccessUnit] {
        collected.removeAll(keepingCapacity: true)
        let result = as_h264_access_finish(native, Self.callback,
                                           Unmanaged.passUnretained(self).toOpaque())
        switch result {
        case ASH264_OK: return collected
        case ASH264_TOO_LARGE: throw Failure.resourceLimit
        default: throw Failure.invalidData
        }
    }
}
