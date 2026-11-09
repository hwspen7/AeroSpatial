import AeroSpatialNative
import Foundation

/// Streaming Annex-B parser backed by the bounded C++ kernel.
/// A NAL is not an access unit, frame, or decoded CVPixelBuffer.
public struct H264Unit: Sendable, Equatable {
    public let type: UInt8
    public let bytes: Data
}

public final class H264UnitAssembler {
    public enum Failure: Error { case invalidNAL, inputTooLarge }
    private let native: OpaquePointer
    private var output: [H264Unit] = []

    public init?(maximumNALBytes: Int = 2 * 1024 * 1024) {
        guard maximumNALBytes > 0, let native = as_h264_create(maximumNALBytes) else {
            return nil
        }
        self.native = native
    }

    deinit { as_h264_destroy(native) }

    private static let callback: @convention(c)
        (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int, UInt8) -> Void = {
        context, source, count, type in
        guard let context, let source else { return }
        let parser = Unmanaged<H264UnitAssembler>.fromOpaque(context).takeUnretainedValue()
        parser.output.append(H264Unit(type: type, bytes: Data(bytes: source, count: count)))
    }

    public func reset() {
        as_h264_reset(native)
        output.removeAll(keepingCapacity: true)
    }

    /// The parser must be used from one serial worker. On malformed input it resets.
    public func accept(_ bytes: Data) throws -> [H264Unit] {
        output.removeAll(keepingCapacity: true)
        let status = bytes.withUnsafeBytes { source in
            as_h264_feed(native, source.bindMemory(to: UInt8.self).baseAddress,
                         bytes.count, Self.callback, Unmanaged.passUnretained(self).toOpaque())
        }
        switch status {
        case ASH264_OK: return output
        case ASH264_TOO_LARGE: throw Failure.inputTooLarge
        default: throw Failure.invalidNAL
        }
    }
}
