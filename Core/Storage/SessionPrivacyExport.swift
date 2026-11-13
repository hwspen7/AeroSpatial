import Foundation

/// Share-only session export. The raw CRC-backed archive remains private.
/// Unknown fields, absolute times, coordinates, notes and original IDs are omitted.
public enum SessionPrivacyExport {
    public enum Failure: Error, Equatable {
        case invalidSource, oversizedLine, malformedRecord, existingDestination, emptySession
    }

    private static let permittedFields: Set<String> = [
        "yaw", "pitch", "roll", "gimbal_pitch", "battery_percent", "target_pitch"
    ]

    /// Produces a new privacy-reduced JSONL file, never modifying the source.
    /// The export is opt-in and does not guarantee custom event identifiers are anonymous.
    @discardableResult
    public static func prepare(source: URL, destination: URL) throws -> Int {
        let source = source.standardizedFileURL
        let destination = destination.standardizedFileURL
        guard source != destination, FileManager.default.fileExists(atPath: source.path) else {
            throw Failure.invalidSource
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw Failure.existingDestination
        }
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".safe-export-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw Failure.invalidSource
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let writer = try FileHandle(forWritingTo: temporary)
        defer { try? writer.close() }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let newSession = "anon-\(UUID().uuidString)"
        let neutralDate = Date(timeIntervalSince1970: 946_684_800)
        var buffer = Data()
        var count = 0
        var originalSession: String?
        var firstUptime: Double?
        var lastUptime: Double?

        func append(_ line: Data) throws {
            guard !line.isEmpty, line.count <= EventContract.maximumLineBytes,
                  let record = try? decoder.decode(SessionRecord.self, from: line),
                  EventContract.accepts(record), record.schemaVersion == 1,
                  let id = record.sessionId, record.sequence == count,
                  originalSession.map({ $0 == id }) ?? true,
                  lastUptime.map({ record.uptime >= $0 }) ?? true else {
                throw Failure.malformedRecord
            }
            if firstUptime == nil { firstUptime = record.uptime }
            let elapsed = record.uptime - (firstUptime ?? record.uptime)
            guard elapsed.isFinite, elapsed >= 0, elapsed <= 366 * 86400 else {
                throw Failure.malformedRecord
            }
            let safe = SessionRecord(
                wallTime: neutralDate.addingTimeInterval(elapsed), uptime: elapsed,
                kind: record.kind, source: record.source,
                fields: record.fields.filter { permittedFields.contains($0.key) },
                note: nil, schemaVersion: 1, sessionId: newSession, sequence: count)
            guard EventContract.accepts(safe) else { throw Failure.malformedRecord }
            let encoded = try encoder.encode(safe)
            guard encoded.count <= EventContract.maximumLineBytes else {
                throw Failure.oversizedLine
            }
            try writer.write(contentsOf: encoded)
            try writer.write(contentsOf: Data([0x0A]))
            originalSession = id
            lastUptime = record.uptime
            count += 1
        }

        while let chunk = try reader.read(upToCount: 32768), !chunk.isEmpty {
            buffer.append(chunk)
            while let end = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                try append(line)
            }
            if buffer.count > EventContract.maximumLineBytes {
                throw Failure.oversizedLine
            }
        }
        guard buffer.isEmpty else { throw Failure.malformedRecord }
        guard count > 0 else { throw Failure.emptySession }
        try writer.synchronize()
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw Failure.existingDestination
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return count
    }
}
