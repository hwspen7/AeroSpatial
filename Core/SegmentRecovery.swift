import AeroSpatialNative
import Foundation

/// Validates each record without loading an entire segment into memory.
/// Only an incomplete *last* record can be repaired. CRC mismatches indicate
/// corruption, not necessarily a torn write, and must never be discarded silently.
public enum SegmentRecovery {
    public enum Failure: Error { case invalidSegment }

    public static func validate(_ url: URL, maximumBytes: Int) throws -> Int {
        try inspect(url, maximumBytes: maximumBytes, repairIncompleteTail: false)
    }

    public static func repair(_ url: URL, maximumBytes: Int) throws -> Int {
        try inspect(url, maximumBytes: maximumBytes, repairIncompleteTail: true)
    }

    private static func inspect(_ url: URL, maximumBytes: Int,
                                repairIncompleteTail: Bool) throws -> Int {
        guard maximumBytes >= 8 else { throw Failure.invalidSegment }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize <= UInt64(maximumBytes) else { throw Failure.invalidSegment }
        var offset: UInt64 = 0
        var incomplete = false
        while offset < fileSize {
            try handle.seek(toOffset: offset)
            let prefix = try handle.read(upToCount: 8) ?? Data()
            if prefix.count != 8 { incomplete = true; break }
            let size = UInt32(prefix[0]) | UInt32(prefix[1]) << 8 |
                UInt32(prefix[2]) << 16 | UInt32(prefix[3]) << 24
            let checksum = UInt32(prefix[4]) | UInt32(prefix[5]) << 8 |
                UInt32(prefix[6]) << 16 | UInt32(prefix[7]) << 24
            guard size > 0, size <= 8 * 1024 * 1024,
                  UInt64(size) + 8 <= UInt64(maximumBytes) - offset else {
                throw Failure.invalidSegment
            }
            let bytes = try handle.read(upToCount: Int(size)) ?? Data()
            if bytes.count < Int(size) { incomplete = true; break }
            let actual = bytes.withUnsafeBytes { as_wire_crc32($0.baseAddress, $0.count) }
            guard checksum == actual else { throw Failure.invalidSegment }
            offset += UInt64(size) + 8
        }
        if incomplete {
            guard repairIncompleteTail else { throw Failure.invalidSegment }
            try handle.truncate(atOffset: offset)
            try handle.synchronize()
        }
        return Int(offset)
    }
}
