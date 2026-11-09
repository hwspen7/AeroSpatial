# Foundation development tracks

This register separates delivered portable interfaces from production and hardware milestones. **An interface or synthetic fixture is not a verified hardware feature.**

| Capability | Current foundation status | Next validation gate |
| --- | --- | --- |
| Versioned multimodal event contract | Implemented, tested | Real source interoperability |
| Causal performance tracing | Implemented, tested on synthetic spans | Instrument actual decoder/inference path |
| Optional-work compute admission | C++ and Swift implemented, parity-tested | Real iPhone thermal/latency profiling |
| Deterministic playback | Existing replay plus seeded overload experiments | Model-specific golden datasets |
| Optical calibration registry | Offline immutable registry implemented | Measure real lens distortion/extrinsics |
| Cross-stream temporal bundling | Metadata-only Swift bundle implemented | Measure sensor/video clock error on devices |
| Camera projection | C++ pinhole ray and reference-plane intersection implemented | Physical camera calibration and accuracy evaluation |
| Algorithm plugin manifests | Swift/Python deterministic dependency planning implemented | Isolated model worker and deployment SDK |
| Model execution | Offline synchronous optional Python callbacks | Sandbox/process supervision and real models |
| Algorithm quality evaluation | Existing quality gates plus span latency summaries | Curated labeled vision datasets |
| Spatial memory | Existing SQLite observation and metadata storage | Live perception evidence/visual relocalization |
| Device capability negotiation | Existing device model plus algorithm readiness decisions | Actual DJI SDK and AirPods hardware verification |
| Data privacy governance | Existing sanitizer plus default-deny offline grant API | End-to-end enforcement, encryption, retention policies |
| Long-running reliability | Existing native soak tests plus repeatable admission experiments | 24-hour target-device soak and performance SLAs |

## Hardware-dependent tasks not represented as complete

Real Mavic Air 2 video decoding, optical calibration, object recognition, real-time inference, camera/body/world transformation measurement, live sensor synchronization, iOS App compilation, AirPods motion capture, and propeller-off DJI control bench tests remain hardware and data acceptance milestones. No aircraft flight commands are added by this track.

## Integration principle

`Kernel/` contains C++ math and resource admission, `Core/` exposes portable Swift contracts, `Toolkit/aerospatial_tools/` is an installable offline utility package. Tests remain in their named root-level folders. Keep filenames domain-based, short and free of temporary stage/version suffixes. Do not introduce deeper directory hierarchies unless required by platform tooling.
