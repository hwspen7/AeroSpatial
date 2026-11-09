import Foundation

public struct ReplayDiagnostics: Equatable, Sendable {
    public var issueCount: Int
    public var issues: [String]
    public var versionedSessions: Int
}

public enum SessionIntegrity {
    /// Validates contiguous per-session sequence and monotonically increasing uptime.
    /// Unversioned legacy events are accepted for backward compatibility.
    public static func inspect(_ records: [SessionRecord]) -> ReplayDiagnostics {
        var issues: [String] = []
        var sessionLast: [String: (sequence: Int, uptime: Double)] = [:]
        var priorUptime: Double?
        for (index, record) in records.enumerated() {
            let number = index + 1
            if !record.uptime.isFinite || record.fields.values.contains(where: { !$0.isFinite }) {
                issues.append("Record \(number) contains a non-finite number")
            }
            if let priorUptime = priorUptime, record.uptime < priorUptime {
                issues.append("Record \(number) decreases uptime")
            }
            priorUptime = record.uptime
            if let version = record.schemaVersion {
                guard version == 1, let id = record.sessionId, !id.isEmpty,
                      let sequence = record.sequence, sequence >= 0 else {
                    issues.append("Record \(number) has incomplete/unsupported schema metadata")
                    continue
                }
                if let previous = sessionLast[id] {
                    if sequence != previous.sequence + 1 {
                        issues.append("Record \(number) has a noncontiguous sequence")
                    }
                    if record.uptime < previous.uptime {
                        issues.append("Record \(number) decreases session uptime")
                    }
                } else if sequence != 0 {
                    issues.append("Record \(number) does not start at sequence zero")
                }
                sessionLast[id] = (sequence, record.uptime)
            } else if record.sessionId != nil || record.sequence != nil {
                issues.append("Record \(number) has unversioned sequence metadata")
            }
        }
        return ReplayDiagnostics(issueCount: issues.count, issues: issues,
                                 versionedSessions: sessionLast.count)
    }
}
