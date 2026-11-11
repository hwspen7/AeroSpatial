# Algorithm platform contract

AeroSpatial's optional-algorithm foundation is deliberately separate from aircraft command authorization, operator control, and device failsafes. It provides deterministic planning, bounded optional-work admission, camera geometry, causal diagnostics, and an offline execution harness. It is **not** a drone autopilot, an untrusted-plugin sandbox, an actual model inference engine, or a real-time deadline guarantee.

## C++ high-frequency compute

`Kernel/src/Runtime/qos.cpp` implements a fixed-table, mutex-synchronized token admission governor. Only streams 3 (video), 4 (perception), and 5 (diagnostic) are accepted. Head motion, telemetry, and aircraft failsafes cannot be throttled through this API. Admission uses bounded burst capacity, monotonic nanosecond timestamps, per-stream refill rates and reported backlog pressure. A rejected optional task is not enqueued or retried. Configuration, invalid timestamps, non-finite estimates, concurrent admission and overload recovery are tested.

`Kernel/src/Geometry/camera.cpp` computes an ideal pinhole camera ray and the ray intersection with a **caller-supplied horizontal ENU reference plane**. Inputs are undistorted pixels using the exact image/crop intrinsics and a verified optical-camera-to-ENU quaternion, with a consistent vertical datum. This is not depth estimation, a map-based geolocation claim, terrain intersection or automatic camera calibration. Native numeric results are available via the Swift `CameraRay` interface.

## Algorithm manifest and dependency planning

`Fixtures/algorithms.json` is a shared test contract. `Core/AlgorithmManifest.swift` and `Toolkit/aerospatial_tools/algorithm.py` validate IDs, input streams, output streams, memory limits, deadlines, dependencies and capability requirements. Only optional output streams 4 and 5 are allowed; attempts to publish new head/aircraft telemetry source streams are rejected. Dependency edges must connect a produced stream to a declared downstream input. Cycles, unknown dependencies, duplicates and registries above 256 entries are rejected. Topological plans are deterministic regardless of registration order.

`Core/AlgorithmDeployment.swift` checks declared hardware requirements and observed input capabilities. Unverified DJI devices are denied hardware-dependent operation. This is advisory readiness, not permission to operate the aircraft.

## Offline algorithm runtime

`Toolkit/aerospatial_tools/runtime.py` can bind known Python callables to validated manifests and execute them synchronously for offline test metadata. It guards optional-work budgets, dependency outcomes, output namespace, payload size, deadlines observed **after return**, failures and quarantine. Hardware-dependent manifests are rejected. Since functions execute in-process, **it cannot interrupt hangs, sandbox untrusted code, enforce OS memory quotas, or guarantee deadlines**. Production model execution would require a separately reviewed worker isolation layer.

## Temporal observability

`Core/PipelineSpan.swift` and `Toolkit/aerospatial_tools/tracing.py` share explicit trace IDs, parent span IDs, monotonic start/end times, clock-domain labels and outcomes. They validate causal ancestry and report per-stage latency/error counts. `Fixtures/traces.jsonl` is a synthetic cross-language example. Spans from different clock domains are **never** merged implicitly. Observed timing is not physical motion completion.

`Toolkit/aerospatial_tools/trace_gate.py` evaluates stage-level minimum sample counts, latency percentiles and error thresholds; missing stages fail closed. This is an experiment quality gate, not an aircraft safety guarantee.

`Core/FrameBundle.swift` forms a video/head/telemetry metadata snapshot only when the existing `MultimodalTimeline` has explicitly normalized timestamps. It rejects stale and uncertainty-exceeding joins and does not retain video bytes or infer target geolocation.

## Calibration and privacy

`Toolkit/aerospatial_tools/calibration.py` maintains immutable optical intrinsics and camera-to-body extrinsics, with version, validity interval, quaternion norm and non-overlapping ranges. Real camera calibration measurements, lens distortion and vehicle-to-world extrinsics are not auto-generated.

`Toolkit/aerospatial_tools/access.py` offers a default-deny, purpose-scoped **application-level** permission check for offline export logic. It is not a secure credential system or filesystem permission enforcement. Applications must call it at each export boundary.

## Reproducibility and commands

```sh
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
swift test
PYTHONPATH=Toolkit python3 -m unittest discover -s ToolkitTests -v
PYTHONPATH=Toolkit python3 -m aerospatial_tools algorithms Fixtures/algorithms.json
PYTHONPATH=Toolkit python3 -m aerospatial_tools trace-audit Fixtures/traces.jsonl
PYTHONPATH=Toolkit python3 -m aerospatial_tools workload --samples 3000 --seed 42
```

Set `AEROSPATIAL_QOS_PROBE=/absolute/path/to/aerospatial-qos-probe` for optional Python/C++ admission parity tests. Performance acceptance requires matched workloads and target-device profiling; smoke tests do not prove low-latency iOS operation.
