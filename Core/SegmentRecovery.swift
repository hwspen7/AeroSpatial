import AeroSpatialNative
import Foundation

/// Scan a journal segment without allocating beyond a single bounded record.
public enum SegmentRecovery {
    public enum Failure: Error { case invalidSegment }

    public static func repair(_ url: URL, maximumBytes: Int) throws -> Int {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        var offset: UInt64 = 0
        while true {
            try handle.seek(toOffset: offset)
            let prefix = try handle.read(upToCount: 8) ?? Data()
            if prefix.isEmpty { return Int(offset) }
            guard prefix.count == 8 else { break }
            let size = UInt32(prefix[0]) | UInt32(prefix[1]) << 8 |
                UInt32(prefix[2]) << 16 | UInt32(prefix[3]) << 24
            let checksum = UInt32(prefix[4]) | UInt32(prefix[5]) << 8 |
                UInt32(prefix[6]) << 16 | UInt32(prefix[7]) << 24
            guard size > 0, UInt64(size) + 8 + offset <= UInt64(maximumBytes) else { break }
            let bytes = try handle.read(upToCount: Int(size)) ?? Data()
            guard bytes.count == Int(size) else { break }
            let actual = bytes.withUnsafeBytes { as_wire_crc32($0.baseAddress, $0.count) }
            guard checksum == actual else { break }
            offset += UInt64(8 + size)
        }
        try handle.truncate(atOffset: offset)
        try handle.synchronize()
        return Int(offset)
    }
}
