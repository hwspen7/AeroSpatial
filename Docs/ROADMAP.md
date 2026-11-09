# AeroSpatial roadmap

## Foundation delivered in source (0.3)

- Unified Swift data contracts for wearable pose, aircraft state, alignment and replay.
- C++17 native kernel for geometry, local ENU, quaternion frames, scalar filtering and pan preview; available through a Swift C ABI bridge and standalone CMake.
- Conservative head-to-pitch mapping with explicit calibration, bounded slew and disarm watchdog.
- Versioned, sequenced JSONL events with Swift/Python validators and seeded fixtures.
- Read-only advisory state machine and quality-gated head/true-north relative bearing.
- Offline Python diagnostics, reproducible synthetic scenarios and local SQLite spatial markers.
- Separate SwiftUI view files, adapter services and an experimental DJI source scaffold.
- Cross-language portable CI plus an opt-in macOS iOS-simulator compile workflow.
- WGS84 ECEF/ENU, quaternion SLERP and transform composition with calibrated frame lookup.
- Sensor quality monitoring and generation-scoped command-ticket interlocks with callback timeout.
- Offline extensible semantic quality audits, regression thresholds, privacy-reduced export and digest manifests.
- Swift virtual-time integration scenarios exercising real control algorithms with deliberate sensor dropout.
- Typed, indexed frame-level perception evidence metadata with strict image-coordinate and provenance rules.

## Next validation gates (must precede live hardware feature claims)

1. Run the manual iOS simulator build on macOS, reconcile any iOS-only compiler issues and verify real-device app lifecycle.
2. Validate `CMHeadphoneMotionManager` sample frames, timestamps, dropout behavior and compatible AirPods model.
3. Confirm DJI MSDK V4 compilation and passive Mavic Air 2 telemetry on the user's exact hardware/firmware.
4. With propellers removed, execute the dedicated gimbal hardware bench plan; measure command response, fault recovery and remaining movement after disarm.
5. Collect real logs and build reproducible latency, jitter and accuracy regression datasets.

## Later extension tracks

**Spatial awareness:** headset/head-world drift estimation, position uncertainty, explicit 3D world-frame transforms and opt-in binaural HRTF playback.

**Intelligent copilot:** passive telemetry feature extraction, energy telemetry calibration, cautiously evaluated safety predictors, operator alerts with confidence and evidence.

**Spatial memory:** camera calibration, synchronized frame metadata, georeferenced camera rays, depth/triangulation when observable, place retrieval and historical change analysis.

**Perception:** decoded video, nonblocking frame timestamping, local target detection/tracking, semantic observations with provenance and uncertainty.

Any aircraft flight-control capability would require a **separate architectural, regulatory and safety review**. It is not part of the current foundation.
