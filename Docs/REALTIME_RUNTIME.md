# Realtime runtime and hardware ingress

The portable core is tested on Linux, Windows and macOS CI where available. A
successful portable test is not a physical iPhone, AirPods or aircraft acceptance.

## P0 engineering changes

| Workstream | Source implementation | Portable verification | Remaining field gate |
| --- | --- | --- | --- |
| Realtime ingestion | `Kernel/realtime.cpp`, `Core/RealtimeHeadIngress.swift`, `Core/LatestSnapshotMailbox.swift` | SPSC wrap/full/concurrent latest, bounded coalescing tests | Measure headset callback latency on iPhone |
| DJI video input | `App/DJIVideoIngress.swift`, `App/DJIVideoPreview.swift`, optional DJIWidget CocoaPod | Existing encoded-video bus tests, iOS simulator compilation when available | DJI SDK compile, live H.264 packets, decoded preview and frame-timing measurement |
| Online clocks | `Core/OnlineClockCoordinator.swift` | Drift, stale mapping, outliers and restart tests | Timestamp sensor/transport clocks on actual devices |
| Device discovery | `Core/CapabilityEvidence.swift`, DJI adapter observation | Unknown model, disconnected, present-but-unverified tests | Compare SDK-observed flags to actual aircraft capability |
| Durable recording | `Core/SegmentJournalSink.swift`, `App/SessionRecorder.swift`, `journal-export` CLI | Ordered async write, restart, capacity, export and corruption tests | iPhone kill/relaunch, storage-full and export/Files app |
| Safety supervisor | `Core/SafetySupervisor.swift`, App arm/tick gates | Every fail-closed branch in portable unit tests | Foreground/background, remote disconnect and propeller-off bench |
| Telemetry and latency | `Core/RuntimeMetrics.swift`, `App/MobileRuntimeHealth.swift` | Percentile/invalid-input tests | Instruments RSS, p95/p99, thermal and energy baseline |
| iOS compilation | `.github/workflows/ios-manual.yml` now runs on push/PR | Not locally available on Linux | Review actual macOS job and SDK-equipped build separately |

## Timing and concurrency

- AirPods motion arrives on the dedicated CoreMotion operation queue. A native
  preallocated SPSC ring handles admission. Every 30 ms the UI consumes the
  latest head sample; intermediate samples count as intentional UI coalescing.
- Flight-state callbacks write into a fixed-size latest-snapshot mailbox.
  The main actor polls it at 20 Hz. Neither mechanism authorizes flight.
- Clock fitting runs only when observations arrive and is throttled to every
  four new accepted pairs after initial calibration. Each source maintains a
  separate bounded history, and predictions are rejected when too old.
- The control gate and disarm watchdog remain on an independent 150 ms tick.
  Command safety uses the actual sample age, not queue consumption time.
- Encoded DJI packets are labelled with **host receipt time** and an estimated
  clock flag. They are **not decoded access units** and are not presented as
  true camera-capture timestamps. DJIWidget supplies an optional UI preview.
- Journal writes are admitted with a fixed in-memory budget and carried out
  on a utility queue. CRC-framed, fsynced segments are authoritative. A write
  failure is surfaced on a later submission or flush. Stopping may block
  until in-flight writes complete; never stop synchronously on a sensor callback.
- `SafetySupervisor` is an additional fail-closed gate. Existing command
  tickets, physical controller priority and firmware failsafes remain essential.
- RSS/thermal metrics are only available on actual iOS. General GPU utilization
  is not available through the public iOS APIs; profile in Instruments.

## Explicit non-goals

The SPSC ring supports **one producer and one consumer** only. It must never be
reused as a multi-producer queue. The observer bus is neither lock-free nor hard
real-time. There is no flight-control API, autonomous mission execution, claim
of exactly-once message delivery, or production-grade video ML pipeline.

## Offline reproduction

```sh
swift test
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
PYTHONPATH=Toolkit python -m unittest discover -s ToolkitTests -v
PYTHONPATH=Toolkit python -m aerospatial_tools journal-export /path/to/flight-directory /path/to/export.jsonl
PYTHONPATH=Toolkit python -m aerospatial_tools validate /path/to/export.jsonl
```

For a hardware acceptance run, record the device, OS, SDK/firmware revision,
CPU, memory, thermal level, p50/p95/p99 latency, drop counters, and full log
integrity. Actual AirPods and DJI hardware gates remain open until witnessed
and measured, regardless of software-test results.
