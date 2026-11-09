# Architecture and ownership boundaries

## Three-language boundary

| Layer | Runtime | Owns | Does not own |
| --- | --- | --- | --- |
| Swift native application | iPhone | Device lifecycle, user consent, head-sample acquisition, snapshot adaptation, safety state, recording and UI | Numeric C++ implementation, offline Python tools |
| Swift portable core | iOS/macOS/Linux | Sensor contracts, freshness checks, capability declarations, replay cursor and advisory rules | Apple frameworks and DJI binary SDK |
| C++17 native kernel | iOS/macOS/Linux/Windows | Deterministic WGS84 geometry, frame rotations, interpolations, scalar filters | Hardware commands, networking, permissions |
| Python offline toolkit | Desktop/CI | Bounded validation, virtual-data audit, quality gates, privacy export, frame parity, SQLite memory | Live drone connections or time-critical control |

## Non-negotiable invariants

1. The physical controller and manufacturer flight safety remain authoritative. No motors, takeoff, landing, navigation or virtual-stick flight commands exist in the foundation.
2. The normal app binary cannot send camera motion to real hardware. A developer-only experimental bench flag is required in addition to operator acknowledgement, a nonflying aircraft, live sensor input and calibration.
3. All input has provenance (`simulator`, `airpods`, `dji`, `app`, `advisor`). Any missing or stale data fails closed.
4. Monotonic uptime is used for all local alignment and sensor-to-command scheduling; wall-clock time is for human logs only.
5. C++ and Swift coordinate frames have documented axes; headphone yaw is not a compass reading and does not measure gaze.
6. Numeric functions reject non-finite values and impossible physical ranges. Local ENU is rejected beyond 50 km from its origin.
7. Offline replays cannot be connected to a live DJI adapter. Recorded marker coordinates are the aircraft's position, never inferred subject coordinates.
8. No cloud backend, microphone stream, face-recognition pipeline or invisible upload is included.
9. A real gimbal command requires a current ticket and fresh source samples. Asynchronous callbacks from an older arm generation are ignored. Timeout or failure inhibits new commands until explicit reset and re-arm.
10. Coordinate frames and altitude datums must match. Unknown relationships cannot be fabricated by the frame graph.

## Motion to pitch path

```text
Headphone sensor -> HeadSample(uptime, yaw, pitch, roll)
                 -> monotonic buffer / freshness check
                 -> baseline calibration
                 -> dead zone / gain / exponential smoother
                 -> slew-rate and absolute pitch clamps
                 -> sensor-health and command-ticket gate
                 -> simulator gimbal OR opt-in bench-only DJI adapter
                 -> versioned command event for offline diagnostics
```

The pitch algorithm issues **absolute target angles**, not continuous flight rates. The application can inhibit **new** commands immediately, but it cannot revoke a motor movement already accepted by DJI. Propellers-off acceptance tests must evaluate the stopping behavior.

## Time, world alignment and angular conventions

- `uptime`: monotonic host seconds since boot, not Unix seconds.
- `wallTime`: UTC ISO-8601 for reporting; never used for control interval calculations.
- `GeoPoint`: decimal degrees, latitude in `[-90,90]`, longitude in `[-180,180]`.
- `RelativePosition`: great-circle distance and clockwise compass bearing, with heading-relative wrapped angle.
- `NativeGeometry.localENU`: approximate east, north, up meters within 50 km. `NativeFrames.enu` uses WGS84 ellipsoidal heights and only accepts a shared vertical datum.
- `NativeGeometry.quaternion`: local right-handed ENU intrinsic ZYX Euler (positive yaw is counterclockwise around up), independent of AirPods intrinsic sensor axes.
- `HeadRelativeAwareness`: stores an explicitly calibrated head yaw and true-north phone-forward direction, then adds the **relative** yaw delta; expires after two minutes. Output is a horizontal left/right stereo preview.
- `DJI` gimbal pitch bounds used by the demo controller: `[-85°,0°]`. This is a conservative application-level setting, **not** proof of physical or SDK operational capability.

## Sensor fusion: what is and is not fused

The synchronizer interpolates neighboring **head angles** with wrap awareness, when their time offsets are within configured bounds. It selects the latest aircraft snapshot at or before the requested time, and never fabricates aircraft positions or extrapolates missing flight telemetry. Phone heading and location remain accuracy-qualified inputs in the application layer.

The C++ α–β filter is available through `NativeSignalFilter` for motion prediction research. It tracks a scalar value and velocity while rejecting out-of-order updates, implausible innovations and long gaps. It does **not** automatically override the already-tested head-pitch control filter.

## Source organization

Small modules remain discoverable by responsibility: `HeadTracking.swift` owns camera mapping; `PassiveAdvisor.swift` owns read-only safety cues; `HeadRelativeAwareness.swift` owns explicit alignment; `ReplayCursor.swift` owns offline time stepping; `NativeGeometry.swift` and `NativeSignalFilter.swift` own C wrappers. C++ files are separated by geometry, orientation and filtering. Python session parsing, validation, analysis, synthesis and SQLite storage each have independent modules.

## Future plugin contracts

- Video frames should carry capture uptime, source ID, camera intrinsics, and synchronized camera pose. A video renderer does not automatically become a detector.
- Semantic observations should distinguish **aircraft coordinates**, **camera ray**, **estimated target coordinates**, confidence and reference frame. Unknown depth must remain unknown.
- Spatial audio should receive a validated world/head transform, elevation confidence and audio device output capabilities. The current pan preview is not binaural HRTF rendering.
- Any future aircraft flight control must be a separate opt-in subsystem with a separate hazard analysis, permissions, watchdogs and field acceptance plan.

## Multimodal data plane

The app receives accepted head and telemetry samples through its established
validation pathway, then mirrors them onto `SpatialBus`. The native C++ ring
handles capacity, per-stream fan-out, payload leases and backpressure. Flight
commands do **not** route through the data bus. See [contract](MULTIMODAL_BUS.md).
