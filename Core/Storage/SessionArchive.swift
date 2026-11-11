import AeroSpatialNative
import Foundation

/// The journal is the authoritative record; JSONL is an explicitly validated export.
/// A crash can leave an incomplete tail, but never requires discarding earlier segments.
public actor SessionArchive {
    public enum Failure: Error { case invalidEvent, wrongOrder, exportExists, corruptArchive }

    private let directory: URL
    private let journal: SegmentJournal
    private let sessionID: String
    private var sequence = 0
    private var lastUptime: TimeInterval?

    public init(directory: URL, segmentBytes: Int = 4 * 1024 * 1024,
                maximumSegments: Int = 16) throws {
        self.directory = directory
        journal = try SegmentJournal(directory: directory, segmentBytes: segmentBytes,
                                     maximumSegments: maximumSegments)
        sessionID = UUID().uuidString
    }

    /// Sequence advances only once the CRC-framed record is durably accepted.
    public func append(_ event: SessionRecord) async throws {
        guard EventContract.accepts(event),
              (lastUptime.map { event.uptime >= $0 } ?? true),
              sequence < Int.max else { throw Failure.invalidEvent }
        var record = event
        record.schemaVersion = 1
        record.sessionId = sessionID
        record.sequence = sequence
        guard EventContract.accepts(record) else { throw Failure.invalidEvent }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(record)
        guard !bytes.isEmpty, bytes.count <= EventContract.maximumLineBytes else {
            throw Failure.invalidEvent
        }
        try await journal.append(bytes)
        sequence += 1
        lastUptime = event.uptime
    }

    public func exportJSONL(to output: URL) throws -> URL {
        try Self.export(directory: directory, to: output)
    }

    /// Export is also usable when recovering a previous session after app restart.
    /// Existing outputs are never silently overwritten.
    public static func recover(directory: URL, to output: URL,
                               segmentBytes: Int = 4 * 1024 * 1024,
                               maximumSegments: Int = 16) throws -> URL {
        _ = try SegmentJournal(directory: directory, segmentBytes: segmentBytes,
                               maximumSegments: maximumSegments)
        return try export(directory: directory, to: output)
    }

    private static func export(directory: URL, to output: URL) throws -> URL {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: output.path) else { throw Failure.exportExists }
        let names = try fm.contentsOfDirectory(atPath: directory.path)
            .filter { $0.range(of: #"^segment-[0-9]{8}\.bin$"#, options: .regularExpression) != nil }
            .sorted()
        guard !names.isEmpty else { throw Failure.corruptArchive }
        let staging = output.deletingLastPathComponent()
            .appendingPathComponent(".export-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: staging.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? fm.removeItem(at: staging) }
        let writer = try FileHandle(forWritingTo: staging)
        defer { try? writer.close() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var nextSequence = 0
        var lastUptime: TimeInterval?
        var sessionID: String?
        for (index, name) in names.enumerated() {
            guard name == String(format: "segment-%08d.bin", index) else {
                throw Failure.corruptArchive
            }
            let handle = try FileHandle(forReadingFrom: directory.appendingPathComponent(name))
            defer { try? handle.close() }
            while true {
                let prefix = try handle.read(upToCount: 8) ?? Data()
                if prefix.isEmpty { break }
                guard prefix.count == 8 else { throw Failure.corruptArchive }
                let count = UInt32(prefix[0]) | UInt32(prefix[1]) << 8 |
                    UInt32(prefix[2]) << 16 | UInt32(prefix[3]) << 24
                let expected = UInt32(prefix[4]) | UInt32(prefix[5]) << 8 |
                    UInt32(prefix[6]) << 16 | UInt32(prefix[7]) << 24
                guard count > 0, count <= EventContract.maximumLineBytes else {
                    throw Failure.corruptArchive
                }
                let bytes = try handle.read(upToCount: Int(count)) ?? Data()
                guard bytes.count == Int(count),
                      bytes.withUnsafeBytes({ as_wire_crc32($0.baseAddress, $0.count) }) == expected,
                      let record = try? decoder.decode(SessionRecord.self, from: bytes),
                      EventContract.accepts(record), record.schemaVersion == 1,
                      record.sequence == nextSequence,
                      let id = record.sessionId,
                      sessionID.map({ $0 == id }) ?? true,
                      lastUptime.map({ record.uptime >= $0 }) ?? true else {
                    throw Failure.corruptArchive
                }
                sessionID = id
                lastUptime = record.uptime
                nextSequence += 1
                try writer.write(contentsOf: bytes)
                try writer.write(contentsOf: Data([0x0A]))
            }
        }
        guard nextSequence > 0 else { throw Failure.corruptArchive }
        try writer.synchronize()
        try fm.moveItem(at: staging, to: output)
        return output
    }
}
