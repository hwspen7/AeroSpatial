# Native data-plane freeze candidate — software evidence

This revision improves the two priority foundations identified before hardware
acceptance and adds a conservative online estimator adapter. It is **not**
a completed hardware validation or safety-certified flight system.

## Encoded video ingress

`as_h264_access_feed_dual` emits NAL diagnostics and AVCC access units in a
single incremental parser pass. Existing NAL and access-unit APIs remain
available. Source resets still require a fresh SPS/PPS and IDR. H.264 slice
handling continues to exclude complex interlaced and exotic streams.

`as_work_queue_pop_lease` transfers ownership of an encoded packet without
copying its bytes after dequeue. The Swift video worker borrows those bytes
only while invoking the native incremental parser. Output NAL diagnostic
payloads and AVCC pictures are still materialized separately. Input into the
queue remains a copy. The queue's `queue_bytes` budget excludes already
popped leases, whose lifetime belongs to the receiver. **This is not a global
memory budget or an end-to-end zero-copy pipeline.** Test memory with actual
`CVPixelBuffer` / `IOSurface` and `VTDecompressionSession` lifetimes.

## Native memory and optional execution

`as_memory_pool_*` provides immutable shared native byte leases, retained
without additional payload copies. Its byte budget remains charged until the
last lease is released, including after pool destruction. Clients must stop
concurrent use before destroying the raw pool handle. There is no implicit
thread-safe lifetime guarantee for a destroyed handle.

`as_executor_*` provides bounded **trusted optional CPU** callbacks across
1–32 native worker threads. It checks queue capacity, relative deadlines,
cancellation of pending tasks and shutdown that joins running callbacks.
An executing callback cannot be preempted or forcibly stopped. The caller owns
callback context until completion or confirmed cancellation. Do not run
untrusted plugins, aircraft control, or watchdog callbacks here. Call
shutdown/destroy only after external submitters have quiesced.

## Online spatial state

`as_fusion_*` wraps the existing 15-error-state ESKF, with separate monotonic
sequence checks for IMU and position observations, timestamp matching,
chi-square innovation rejection, and explicit unhealthy state after a long
IMU gap. It requires real calibrated ENU positions, body-frame specific force,
measured noise, and a known initial pose. **Delayed position observations are
rejected**, not silently applied to a later state. Re-initialize a new engine
after a declared gap. This estimator is not wired to DJI or flight commands;
there is no claim that the Mavic Air 2 exposes a usable raw IMU stream.

## Verification

- Debug CMake/CTest runs native assertions, including new dual-parser, lease,
  executor, and online fusion suites.
- Swift Package unit tests exercise the native interfaces through the C ABI.
- Python toolkit regression, synthetic sessions and integrity checks are run
  by `Scripts/run-checks.sh`.
- ASan/UBSan validate native memory and undefined behavior on the available
  environment; concurrency correctness still requires device stress tests.
- GitHub Linux, Windows, and iOS simulator workflows must be checked for the
  **exact commit** before CI acceptance is claimed.

## Mandatory physical validation

DJI MSDK linking on a supported iPhone, actual Mavic Air 2 H.264 feed,
VideoToolbox decoded pixels, source/capture time mapping, model execution,
headphone source timestamps, camera/IMU extrinsics and calibration, 24-hour
thermal/memory workload, p95/p99 capture-to-observation latency, reconnect
resynchronization, and propeller-off stop/interlock testing remain required.
No live aircraft flight-control command path was added by this revision.
