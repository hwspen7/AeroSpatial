# C++ video access units and bounded runtime processing

## Scope

The real-time video foundation contains two independent, explicitly bounded native components. This is a portable video **transport/assembly** and a best-effort task scheduler, not an aircraft control channel, a hard-real-time guarantee, or a certified DJI decoder.

### 1. Encoded video to decoded pixels

```
DJI MSDK V4 encoded callback
    -> VideoPacketPublisher (reception clock explicitly estimated)
    -> C++ ASWorkQueue (deadline, bounded events/bytes, priority)
    -> one serial Swift worker
    -> C++ Annex-B incremental NAL parser
    -> C++ access-unit assembly (AUD / first_mb_in_slice boundaries)
    -> AVCC picture + SPS / PPS
    -> iOS CoreMedia CMSampleBuffer
    -> VideoToolbox VTDecompressionSession
    -> CVPixelBuffer callback for a trusted optional model consumer
```

The C++ assembler exports a stable C ABI in `Kernel/include/aerospatial_access_unit.h`. NAL units remain available on the existing native bus for diagnostics and backwards compatibility. Graceful EOS emits the last NAL and access unit, while a disconnect or forced
close explicitly discards the unverified tail. Assemblers require SPS, PPS,
and a new IDR after resets; they never silently treat one SDK callback as one picture. Parameter changes recreate the VideoToolbox format/session. Native callbacks borrow their storage only while executing; Swift copies access units before asynchronous use. The VideoToolbox bridge is Apple-specific and must remain in Swift; portable C++ cannot directly use iOS frameworks.

The encoded stream uses an **estimated SDK callback receipt timestamp**, not a DJI-provided camera exposure timestamp, verified PTS/DTS, or real time. PTS is provisionally monotonic and appropriate for basic streams without complex reordering. The parser uses AUD or `first_mb_in_slice` to delimit pictures; interlaced, field-coded, partitioned and other exotic H.264 configurations are **not** production-validated. Support for B-frame reorder, true capture timestamps, complex slice-header picture identity, AV1, H.265 and arbitrary codec switching is outside this implementation. A decoder-ready packet alone does not prove that a physical DJI controller supplied a valid stream.

### 2. Native bounded work admission

`Kernel/work_queue.cpp` provides `as_work_queue_*` with a fixed event cap, byte cap and per-payload cap. The highest-priority class is for **non-actuating essential observations**, not flight commands or watchdogs. Essential work may evict lower-priority optional work but may never evict an existing essential entry. Optional work uses explicit reject-newest behavior. All work has a caller-domain monotonic receipt time and absolute deadline. Expired jobs are discarded, and the metadata reports rejection, evictions, expiration, memory high-water and maximum queue wait. The queue is thread-safe through a mutex; it makes no lock-free or hard-real-time claims.

`VideoPacketPublisher` uses this native queue with coalesced Swift wakeups instead of a separate Swift data-envelope queue per callback. The producer checks timestamp monotonicity, sends the physical receipt value inside the payload, and always marks the next accepted fragment as discontinuous after a rejected packet. The C++ queue uses **host dispatch monotonic clock values**, which must not be confused with source capture times. The video worker uses a reusable 2 MiB scratch buffer to minimize per-frame temporary allocations.

`App/ControlCadence.swift` schedules the 150 ms control tick on its own monotonic Dispatch timer. It coalesces outstanding ticks instead of unbounded MainActor enqueues; execution of the safety state machine remains on MainActor. Its C++ latency histogram separately measures dispatch-to-actor completion. This mitigates UI timer stalls but does **not** make the control loop real-time or bypass hardware failsafes. The existing command gate, explicit bench-only authorization and physical remote remain authoritative.

### Quality signals

- Raw video callbacks admitted/rejected, native deadline-expired samples and native queue occupancy
- Per-stage native p95 bucket **upper bounds** for queue and processing latency
- NAL units published and complete access units emitted
- VideoToolbox accepted/decoded/rejected/queue-dropped units
- Control-loop execution and scheduling p95 upper bounds, coalesced tick count
- Faults fail closed, drop optional work and demand an IDR resynchronization

The fixed-bin log2 histogram is intentionally approximate. Use Instruments plus actual AirPods, iPhone and Mavic Air 2 logs before setting production p95/p99 and thermal targets.

## Reproducible verification

```
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
swift test
PYTHONPATH=Toolkit python3 -m unittest discover -s ToolkitTests
```

`Fixtures/h264-six-frames.264` is an original tiny black 64x64 baseline stream created with FFmpeg/libx264 (10 fps, GOP 3, no B frames, `aud=1`, repeated SPS/PPS) to validate actual encoded-byte boundaries. `test_h264_real.cpp` performs 100 seeded random callback partitions, comparing complete access units, lengths, IDR flags and SPS/PPS. `test_access_unit.cpp` covers malformed inputs, missing headers, reset and multislice assembly. `test_work_queue.cpp` covers concurrency, expiration, byte caps, overload and essential priority. `Tests/AccessUnitAndQueueTests.swift` checks C ABI bridging. This fixture is self-generated and redistributable.

## Mandatory remaining device evidence

1. GitHub macOS simulator compile for the specific commit. Device code must additionally link DJI MSDK V4 on a compatible Mac/Xcode build.
2. Physical Mavic Air 2 stream, firmware and remote details, actual SPS/PPS dimensions, decoder capability and source timestamp semantics.
3. Repeatable pixel-buffer outputs from VideoToolbox with verified frame timing and a real Core ML model artifact.
4. Measured capture-to-display / capture-to-model latency, decoded FPS, peak memory, GPU/ANE usage, iPhone thermal behavior and reconnect recovery.
5. Propeller-off safety checks, manual controller ownership and no flight control path.

Do not mark these physical acceptance gates passed from this portable release alone.
