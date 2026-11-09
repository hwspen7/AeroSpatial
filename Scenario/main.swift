import Foundation
import AeroSpatialCore

let args = Array(CommandLine.arguments.dropFirst())
guard (1...4).contains(args.count),
      let duration = args.count > 1 ? Int(args[1]) : 10,
      let seed = args.count > 2 ? Int(args[2]) : 7,
      let dropout = args.count > 3 ? Int(args[3]) : nil else {
    fputs("Usage: aerospatial-scenario OUTPUT.jsonl [duration_seconds] [seed] [dropout_start_second]\n", stderr)
    exit(2)
}
do {
    let config = ScenarioSettings(seed: seed, durationSeconds: duration,
                                  headDropoutStart: dropout, headDropoutDuration: dropout == nil ? 0 : 2)
    let records = try ScenarioRunner.generate(config)
    let data = try SessionReplay.encodeJSONL(records)
    try data.write(to: URL(fileURLWithPath: args[0]), options: .atomic)
    print("Generated \(records.count) Swift control-loop records. No hardware was accessed.")
} catch {
    fputs("Scenario failed: \(error)\n", stderr)
    exit(2)
}
