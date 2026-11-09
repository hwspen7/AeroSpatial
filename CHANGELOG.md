## Multimodal transport foundation

- Added a C++17 per-stream bounded publish/subscribe bus with explicit backpressure,
  source clock domains, quality flags, independent subscriber cursors and missed-event accounting.
- Added shared payload leases for zero-copy native fan-out with bounded outstanding
  leases and defensive validation at the C ABI boundary.
- Added typed Swift ingress for accepted head motion and aircraft telemetry,
  plus extension interfaces for encoded video and perception metadata.
- Added streaming Python metadata audit, reproducible fixtures, native concurrency
  tests, Linux sanitizer acceptance and a standalone transport microbenchmark.
- Preserved the existing command authorization layer. This bus is not a flight
  control system or live video decoding pipeline.

# Changelog

## Current foundation upgrade

- Flattened package layout to purpose-named top-level modules; removed language-named folders and version-suffixed fixture filenames.
- Replaced linear sensor synchronizer scans and array front-removals with a capacity-bounded timestamp ring.
- Added monotonic clock-offset estimation with drift bounds and outlier rejection.
- Added load-aware governor for non-safety-critical visualization and analytics.
- Added allocation-free native C++ bulk WGS84 and low-pass primitives with a Swift facade.
- Added Python event-aware telemetry reduction, online streaming statistics, and offline performance command.
- Added new native, Swift and Python correctness tests and microbenchmark tools.
- Preserved conservative command interlocks and DJI hardware-bench-only boundaries.

# Changelog

## 0.3.0 — Reliability, geometry and extensibility (2026-11-09)

- Added WGS84 ellipsoidal ECEF/ENU conversions, quaternion interpolation/inversion/composition and a calibrated, bounded spatial frame graph across native C++, portable Swift and Python reference tests.
- Introduced a monotonic sensor health monitor and generation-scoped single-in-flight gimbal command gate with timeout, stale-data suppression and explicit re-arm recovery.
- Connected health monitoring and command gating to the iOS application simulation/experimental bench logic, including link-down event delivery and diagnostics UI.
- Hardened event contracts and the on-device session recorder with bounded fields/notes, monotonic write checks and cross-language parsing rules.
- Added reproducible Swift virtual-time end-to-end control scenarios and Python seeded fault injection, semantic audits, declarative quality gates and explicit extension rules.
- Added opt-in privacy-reduced JSONL export and SHA-256 file-integrity manifests with clear non-authentication limitations.
- Added typed local perception-evidence metadata storage with normalized camera-image boxes and session-frame provenance, without claiming video detection or object geolocation.
- Strengthened battery-alert hysteresis, simulator timestamp handling and portable CI and development documentation.
- No change to the production policy: physical drone camera actuation stays disabled in the standard build; flight control is absent and iOS/DJI hardware remains unverified.

## 0.2.0 — Foundation expansion (2026-11-09)

- Added independently compiled C++17 geometry, quaternion rotation, stereo pan and α–β filtering primitives with a stable C ABI and CMake/CTest.
- Integrated native C++ operations with the portable Swift package and expanded XCTest coverage.
- Implemented freshness- and compass-quality-gated head-relative horizontal awareness, conservative capability contracts and passive advisory logic.
- Added deterministic seekable `ReplayCursor`, sequenced v1 JSONL records and Swift integrity diagnostics.
- Built Python offline validators, synthetic scenario generation, session reports and C++ geodesy parity tests.
- Added private, local SQLite spatial observation memory and idempotent camera-marker ingestion.
- Refactored application model and dashboard into smaller Swift files and added diagnostic cards and recorded camera marks.
- Disabled live DJI pitch output in standard builds; only a propeller-off developer build can opt in for bench validation.
- Added multi-language CI and a manual macOS iOS-simulator compilation workflow, extensive contracts and testing documents.

## 0.1.0 — Initial foundation

- Portable Swift geometry, time synchronization, pitch mapping, JSONL replay, SwiftUI simulator and experimental DJI adapter source.
