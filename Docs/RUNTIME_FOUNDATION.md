# Runtime foundation acceptance and limitations

The observation-only runtime includes the following independent, small modules.

| Requirement | Implementation | Portable acceptance | Remaining integration |
| --- | --- | --- | --- |
| P0 real-time ingress | `RealtimeIngress` bounded O(1) dual-lane ring | Priority, rejection, overwrite, bounded drain | `SpatialIngressPublisher` moves bus encoding/publication off `MainActor`; head control state remains on main, profile on iPhone |
| P0 video and sensor pipeline | `DeviceVideoPipeline`, `VideoSensorPipeline` | Encoded video published into native bus; strict three-stream metadata join | DJI SDK callbacks, VideoToolbox decoding, buffer lifetime on device |
| P0 online clock model | `OnlineClockRegistry` using bounded robust C++ fit | Domain separation, outlier rejection, reset, explicit uncertainty | Paired AirPods/video/drone hardware timestamps |
| P0 capability discovery | `DeviceEvidence` + `DeviceDiscovery` | Expiry and unverified fail-closed behavior | Actual MSDK firmware/gimbal capability interrogation |
| P0 persistence | `AsyncJournalWriter` + existing `SegmentJournal` | Actor-serialized CRC-framed durable writes and recovery | App `SessionRecorder` now uses bounded serial background JSONL writes; migrate export to journal format and enforce retention |
| P0 supervision | `SafetySupervisor` | Stale head/telemetry, disconnection, flying, authorization gates | Wire as independent safety check in actual bench app |
| P0 performance | C++ `runtime_metrics.cpp` atomic log histogram, Swift facade | Multithreaded metrics and native C ABI tests | Thermal/energy/I/O load on iPhone; p99 SLO based on real data |
| P0 device CI | `ios-manual.yml` now runs on pushes and PRs | macOS simulator build gate configured | Observe GitHub CI result; physical tests always separate |

## Safety boundaries

* There are **no autonomous flight commands** and the observation transport cannot authorize aircraft motion.
* A `DeviceEvidence.verified` value is a local engineering observation, not a signed remote attestation or DJI capability guarantee.
* The histogram uses log2 duration buckets. Reported p95/p99 are **upper bucket bounds**, not precise quantiles.
* `OnlineClockRegistry` is intended for low-rate clock calibration anchor pairs, not each raw IMU/video sample. Uncertainty is an estimate, not a certified bound.
* The real camera adapter, CVPixelBuffer sharing, `VideoToolbox` decoder, and DJI MSDK interop are **not completed or validated** here. The pipeline only consumes already encoded frames.
* The UI now queues bounded JSONL writes off the main thread and flushes in background. The segmented journal remains independent; a full unified export/index/retention migration has **not** been completed.
* Tests run on Linux/Windows are not a substitute for signed iOS, AirPods and propeller-off DJI hardware verification.

## Test gates

Run `swift test`, `ctest --test-dir build-native`, and `PYTHONPATH=Toolkit python3 -m unittest discover -s ToolkitTests`.
A macOS iOS-simulator workflow now triggers automatically. Results must be confirmed from GitHub Actions, and any failure must be investigated rather than assumed to be infrastructure.

## App integration

`SpatialIngressPublisher` runs accepted head and aircraft observations through a bounded `AsyncStream` into a single Swift worker, publishing to the native C++ bus without JSON serialization in the UI callback. When its buffer is full, it rejects new observations rather than blocking the UI. This does not remove the main-actor state machine used for display and the experimental gimbal authorization.

The application JSONL writer now uses a 512-slot admission semaphore and serial background writes. The session-completion callback runs only after disk synchronization/close. Queue backpressure causes the recorder to stop, not to silently grow without a bound.
