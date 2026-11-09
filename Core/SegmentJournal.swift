import AeroSpatialNative
import Foundation

/// Append-only CRC-protected storage. Rotation is bounded and never deletes logs.
/// Storage is separate from aircraft command authorization.
public actor SegmentJournal {
    public enum Failure: Error { case invalidLimits, limitReached, invalidRecord }

    private let directory: URL
    private let segmentBytes: Int
    private let maximumSegments: Int
    private var currentID: Int = 0
    private var currentBytes: Int = 0
    private var count: Int = 0

    public init(directory: URL, segmentBytes: Int = 4 * 1024 * 1024,
                maximumSegments: Int = 16) throws {
        guard segmentBytes >= 1024, segmentBytes <= 1_073_741_824,
              maximumSegments >= 1 && maximumSegments <= 10000 else { throw Failure.invalidLimits }
        self.directory = directory
        self.segmentBytes = segmentBytes
        self.maximumSegments = maximumSegments
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.range(of: #"^segment-[0-9]{8}\.bin$"#, options: .regularExpression) != nil }
            .sorted()
        if let first = names.first, !first.hasPrefix("segment-00000000") {
            throw Failure.invalidRecord
        }
        for (index, name) in names.enumerated() {
            guard name == String(format: "segment-%08d.bin", index) else { throw Failure.invalidRecord }
            let path = directory.appendingPathComponent(name)
            let recovered = try SegmentRecovery.repair(path, maximumBytes: segmentBytes)
            currentBytes = recovered
            count += 1
            currentID = Int(name.dropFirst(8).prefix(8)) ?? 0
        }
    }

    public func append(_ data: Data) throws {
        guard !data.isEmpty, data.count <= min(8 * 1024 * 1024, segmentBytes - 8) else {
            throw Failure.invalidRecord
        }
        let rotate = count > 0 && currentBytes + data.count + 8 > segmentBytes
        let nextCount = count == 0 ? 1 : count + (rotate ? 1 : 0)
        guard nextCount <= maximumSegments else { throw Failure.limitReached }
        let nextID = currentID + (rotate ? 1 : 0)
        let path = directory.appendingPathComponent(String(format: "segment-%08d.bin", nextID))
        if !FileManager.default.fileExists(atPath: path.path) {
            guard FileManager.default.createFile(atPath: path.path, contents: Data()) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: path)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let crc = data.withUnsafeBytes { as_wire_crc32($0.baseAddress, $0.count) }
        var header = Data()
        for value in [UInt32(data.count), crc] {
            for offset in [0, 8, 16, 24] { header.append(UInt8(truncatingIfNeeded: value >> offset)) }
        }
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        currentID = nextID
        count = nextCount
        currentBytes = (rotate ? 0 : currentBytes) + data.count + 8
    }
}
