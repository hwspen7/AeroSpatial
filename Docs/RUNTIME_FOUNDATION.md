# Runtime foundation acceptance and limitations

The observation-only runtime includes the following independent, small modules.

| Requirement | Implementation | Portable acceptance | Remaining integration |
| --- | --- | --- | --- |
| P0 real-time ingress | `RealtimeIngress` bounded O(1) dual-lane ring | Priority, rejection, overwrite, bounded drain | `SpatialIngressPublisher` moves bus encoding/publication off `MainActor`; head control state remains on main, profile on iPhone |
| P0 video and sensor pipeline | `DeviceVideoPipeline`, `VideoSensorPipeline` | Encoded video published into native bus; strict three-stream metadata join | DJI SDK callbacks, VideoToolbox decoding, buffer lifetime on device |
| P0 online clock model | `OnlineClockRegistry` using bounded robust C++ fit | Domain separation, outlier rejection, reset, explicit uncertainty | Paired AirPods/video/drone hardware timestamps |
| P0 capability discovery | `DeviceEvidence` + `DeviceDiscovery` | Expiry and unverified fail-closed behavior | Actual MSDK firmware/gimbal capability interrogation |
| P0 persistence | `AsyncJournalWriter` + existing `SegmentJournal` | Actor-serialized CRC-framed durable writes and recovery | App `SessionRecorder` now writes the CRC-framed `SessionArchive` through a bounded background worker, and exports validated JSONL on completion. Retention automation and device storage profiling remain pending |
| P0 supervision | `SafetySupervisor` | Stale head/telemetry, disconnection, flying, authorization gates | Wire as independent safety check in actual bench app |
| P0 performance | C++ `runtime_metrics.cpp` atomic log histogram, Swift facade | Multithreaded metrics and native C ABI tests | Thermal/energy/I/O load on iPhone; p99 SLO based on real data |
| P0 device CI | `ios-manual.yml` now runs on pushes and PRs | macOS simulator build gate configured | Observe GitHub CI result; physical tests always separate |

## Safety boundaries

* There are **no autonomous flight commands** and the observation transport cannot authorize aircraft motion.
* A `DeviceEvidence.verified` value is a local engineering observation, not a signed remote attestation or DJI capability guarantee.
* The histogram uses log2 duration buckets. Reported p95/p99 are **upper bucket bounds**, not precise quantiles.
* `OnlineClockRegistry` is intended for low-rate clock calibration anchor pairs, not each raw IMU/video sample. Uncertainty is an estimate, not a certified bound.
* The real camera adapter, CVPixelBuffer sharing, `VideoToolbox` decoder, and DJI MSDK interop are **not completed or validated** here. The pipeline only consumes already encoded frames.
* The UI now stores authoritative CRC-framed segments through a bounded worker and exports validated JSONL on successful stop. Archive recovery is available after app restart. Automatic retention, disk quota management and physical-device testing are **not** complete.
* Tests run on Linux/Windows are not a substitute for signed iOS, AirPods and propeller-off DJI hardware verification.

## Test gates

Run `swift test`, `ctest --test-dir build-native`, and `PYTHONPATH=Toolkit python3 -m unittest discover -s ToolkitTests`.
A macOS iOS-simulator workflow now triggers automatically. Results must be confirmed from GitHub Actions, and any failure must be investigated rather than assumed to be infrastructure.

## App integration

`SpatialIngressPublisher` runs accepted head and aircraft observations through a bounded `AsyncStream` into a single Swift worker, publishing to the native C++ bus without JSON serialization in the UI callback. When its buffer is full, it rejects new observations rather than blocking the UI. This does not remove the main-actor state machine used for display and the experimental gimbal authorization.

The application JSONL writer now uses a 512-slot admission semaphore and serial background writes. The session-completion callback runs only after disk synchronization/close. Queue backpressure causes the recorder to stop, not to silently grow without a bound.

## Airframe target and reuse

The numerical kernel, time alignment, event bus, journal, vision metadata and algorithm
interfaces are aircraft-agnostic. `Core/AircraftProfile.swift` recognizes DJI Mavic Air 2
and DJI Air 2S as **different** models. The experimental DJI SDK adapter accepts only
the initial Mavic Air 2 target and does not infer a verified gimbal capability merely
from the model. Other aircraft require a separately validated adapter. A successful
SDK connection is not equivalent to physical flight or gimbal acceptance.

## Archive recovery and integrity

`SessionArchive` is the authoritative, bounded CRC-framed session record. The app
exports the original session JSONL format **after** the worker has drained and the
archive passes record-order, checksum and schema validation. It returns a failure
instead of reporting an unverified export as saved. On restart, callers can invoke
`SessionArchive.recover(directory:to:)` for a previous session. Only an incomplete
last record in the final segment is repairable. A CRC mismatch or earlier-segment
corruption fails closed to avoid silently erasing previously accepted evidence.

Not complete: real AirPods/DJI hardware timestamps, genuine Mavic Air 2 video
callback and decoder integration, signed iPhone build, live firmware capability
probing, and a 24-hour device soak. These cannot be passed through simulation.

## Video-source integration update

`DJIEncodedVideoReceiver` registers a serial `DJIVideoFeedListener` callback
only when the exact Mavic Air 2 model is observed by MSDK V4. The callback
passes bounded encoded fragments to `VideoPacketPublisher` without updating
SwiftUI. `Kernel/h264.cpp` reassembles fragmented Annex-B start codes into NAL
units. All timestamps are SDK callback receipt-time estimates and carry
`clockEstimated`/`lowConfidence` quality flags. Disconnection unregisters the
listener and marks stream discontinuity. See `Docs/P0_ACCEPTANCE.md` for the
remaining decoder, SDK, and physical acceptance gates.

`SpatialIngressPublisher` now exposes accepted, rejected, published and native
rejected counters. These describe transport outcomes, not real-world delivery
or complete aircraft command acknowledgements.
