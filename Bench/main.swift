import AeroSpatialCore
import Foundation

let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 100_000
if count < 1 || count > 2_000_000 {
    fputs("Sample count must be between 1 and 2000000\n", stderr)
    exit(2)
}
var synchronizer = SensorSynchronizer(capacity: 4096, maximumHeadOffset: 0.05)
let started = ProcessInfo.processInfo.systemUptime
var matched = 0
for index in 0..<count {
    let time = Double(index) * 0.01
    _ = synchronizer.append(HeadSample(uptime: time,
        pose: HeadPose(yaw: Double(index % 360), pitch: 10, roll: 0)))
    if synchronizer.aligned(at: time).head != nil { matched += 1 }
}
let elapsed = max(1e-9, ProcessInfo.processInfo.systemUptime - started)
let metrics: [String: Any] = [
    "operation": "sensor_ring_insert_and_lookup",
    "samples": count,
    "matched": matched,
    "seconds": elapsed,
    "samples_per_second": Double(count) / elapsed
]
let bytes = try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys])
print(String(decoding: bytes, as: UTF8.self))
