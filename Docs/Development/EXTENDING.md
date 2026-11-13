# Building on AeroSpatial

AeroSpatial intentionally separates real-time device control, portable numerical kernels, and offline workflows. New capabilities must not bypass those boundaries.

## Swift extension points

- **New sensors:** Produce `HeadSample` or a dedicated typed sample with a monotonic timestamp and explicit coordinate-frame documentation. Use `SensorHealthMonitor` to reject invalid, future or repeated timestamps before `SensorSynchronizer`.
- **New aircraft adapters:** Implement the app's `DroneAdapter` protocol under `App`. Declare conservative `DeviceCapabilities`, never set `canCommandFlight`, and implement `disconnect()` plus explicit command callbacks. Live pitch is build-gated in `BenchSafety` and separately restricted by `GimbalCommandGate`.
- **New spatial algorithms:** Build against `SpatialTransform`, `FrameGraph`, `NativeFrames`, `HeadRelativeAwareness` and explicit frame IDs. Do not conflate a relative DJI takeoff altitude with an ellipsoidal GPS height.
- **New advisory rules:** Keep them pure and read-only like `PassiveAdvisor`. Distinguish measured telemetry from estimates and warn when supporting samples are stale.
- **New UI:** Put screens in `App` and subscriptions in application services, not inside portable mathematical code.

## C++ numerical extensions

Add a single-purpose `.cpp` file under the relevant `Kernel/<Subsystem>/` directory and add its declarations to `include/aerospatial_native.h`. Export only plain C-compatible structs, arrays and error codes. Include the source in `Kernel/CMakeLists.txt`, add a corresponding `NativeTests/<Subsystem>/test_*.cpp`, and use a thin checked Swift wrapper. No C++ exceptions or owned pointers can cross the C ABI.

The C++ library is built both through Swift Package Manager and standalone CMake, so each new function must compile without DJI or Apple-only headers.

## Frame-level perception evidence

`perception_models.FrameObservation` validates the model identifier, session/frame provenance, capture uptime, confidence and normalized 2D bounding box in the `camera_image` frame. `PerceptionStore` persists these records in SQLite with indexed queries. This is metadata storage, not a detector, tracking engine, image database or a claim of object geolocation. Integrations should add actual camera timing, intrinsics, and uncertainty before any mapping to geographic coordinates.

## Python audit extensions

`aerospatial_tools.audit_models.AuditRule` is an explicit rule protocol with `name` and `inspect(events)`. Pass concrete rule objects to `audit(path, rules=(...))`. There is **no** automatic loading of unknown packages or modules from log files. Future rules can investigate frame validity, calibration coverage, stale camera timestamps, tracking confidence and perception provenance.

```python
from aerospatial_tools.audit import audit
from aerospatial_tools.audit_models import Finding

class ObservationRule:
    name = "observation_provenance"

    def inspect(self, events):
        return [Finding("missing_frame_id", "warning", event.sequence,
                        "Observation has no camera frame identifier")
                for event in events
                if event.kind == "observation" and "frame_id" not in event.fields]

report = audit(path_to_session, rules=(ObservationRule(),))
```

## Required tests and evidence

Every extension should include a positive case, a malformed input case, an out-of-order or stale data case and a deterministic replay. Hardware features require a **separate** macOS/Xcode/device acceptance result; neither Linux unit tests nor the simulator validate a physical flight controller.

The current v1 JSONL format supports numeric fields and a short note only. Rich video/perception schemas should introduce a separately versioned protocol with explicit unit and provenance metadata rather than silently changing v1 semantics.
