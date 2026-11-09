import Foundation

/// Narrow v1 wire-format contract. This module is independent of any recorder or SDK.
public enum EventContract {
    public static let maximumLineBytes = 1_000_000
    public static let maximumFields = 128
    public static let maximumNoteBytes = 4096

    public static func accepts(_ record: SessionRecord) -> Bool {
        guard record.uptime.isFinite, record.uptime >= 0,
              record.wallTime.timeIntervalSince1970.isFinite,
              validIdentifier(record.kind, maxLength: 96),
              validIdentifier(record.source, maxLength: 96),
              record.fields.count <= maximumFields,
              record.note.map({ $0.utf8.count <= maximumNoteBytes }) ?? true,
              record.fields.allSatisfy({ validIdentifier($0.key, maxLength: 96) && $0.value.isFinite })
        else { return false }
        if let version = record.schemaVersion {
            guard version == 1,
                  let session = record.sessionId, validIdentifier(session, maxLength: 128),
                  let sequence = record.sequence, sequence >= 0 else { return false }
        } else if record.sessionId != nil || record.sequence != nil {
            return false
        }
        return true
    }

    private static func validIdentifier(_ input: String, maxLength: Int) -> Bool {
        !input.isEmpty && input.utf8.count <= maxLength &&
        input.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" ||
                                         $0 == "-" || $0 == "." || $0 == ":") }
    }
}
