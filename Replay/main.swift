import Foundation
import AeroSpatialCore

let args = CommandLine.arguments
if args.count != 2 || args[1] == "--help" {
    print("Usage: aerospatial-replay path/to/session.jsonl")
    exit(args.count == 2 ? 0 : 2)
}
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let records = try SessionReplay.decodeJSONL(data)
    let summary = SessionReplay.summarize(records)
    print("Records: \(summary.totalRecords)")
    print(String(format: "Duration: %.2f seconds", summary.durationSeconds))
    for (kind, count) in summary.recordsByKind.sorted(by: { $0.key < $1.key }) {
        print("  \(kind): \(count)")
    }
    print("Out-of-order: \(summary.nonmonotonicRecords)")
    print("Invalid numeric: \(summary.invalidNumericFields)")
    let diagnostics = SessionIntegrity.inspect(records)
    print("Schema sessions: \(diagnostics.versionedSessions)")
    print("Integrity issues: \(diagnostics.issueCount)")
    for issue in diagnostics.issues.prefix(10) { print("  \(issue)") }
    if diagnostics.issueCount != 0 { exit(1) }
} catch {
    fputs("Replay failed: \(error)\n", stderr)
    exit(1)
}
