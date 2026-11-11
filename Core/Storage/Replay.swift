import Foundation

public struct ReplaySummary: Equatable, Sendable {
    public var totalRecords: Int
    public var recordsByKind: [String: Int]
    public var durationSeconds: Double
    public var nonmonotonicRecords: Int
    public var invalidNumericFields: Int
}

public enum ReplayError: Error, Equatable {
    case invalidJSONLine(Int)
    case invalidEncoding
}

public enum SessionReplay {
    public static func decodeJSONL(_ data: Data) throws -> [SessionRecord] {
        guard let text = String(data: data, encoding: .utf8) else { throw ReplayError.invalidEncoding }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [SessionRecord] = []
        for (idx, line) in text.components(separatedBy: .newlines).enumerated() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard line.utf8.count <= EventContract.maximumLineBytes,
                  let entry = try? decoder.decode(SessionRecord.self, from: Data(line.utf8)),
                  EventContract.accepts(entry) else {
                throw ReplayError.invalidJSONLine(idx + 1)
            }
            entries.append(entry)
        }
        return entries
    }

    public static func encodeJSONL(_ records: [SessionRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var output = Data()
        for (index, record) in records.enumerated() {
            guard EventContract.accepts(record) else {
                throw ReplayError.invalidJSONLine(index + 1)
            }
            output.append(try encoder.encode(record))
            output.append(0x0A)
        }
        return output
    }

    public static func summarize(_ records: [SessionRecord]) -> ReplaySummary {
        var counts: [String: Int] = [:]
        var invalid = 0
        var nonmonotonic = 0
        var previous: Double?
        for record in records {
            counts[record.kind, default: 0] += 1
            if record.fields.values.contains(where: { !$0.isFinite }) || !record.uptime.isFinite { invalid += 1 }
            if let previous = previous, record.uptime < previous { nonmonotonic += 1 }
            previous = record.uptime
        }
        let duration = records.isEmpty ? 0 : max(0, (records.last?.uptime ?? 0) - (records.first?.uptime ?? 0))
        return ReplaySummary(totalRecords: records.count, recordsByKind: counts,
                             durationSeconds: duration,
                             nonmonotonicRecords: nonmonotonic,
                             invalidNumericFields: invalid)
    }
}
