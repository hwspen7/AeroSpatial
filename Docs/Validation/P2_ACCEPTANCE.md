# P2 acceptance matrix — portable software and device integration

A module is portable-complete only after implementation, negative tests and
cross-platform CI. A product feature is complete only after the relevant
hardware, real-world dataset and integration gates pass.

| P2 capability | Portable implementation / tests | Still needed for product acceptance |
| --- | --- | --- |
| 19. Public developer SDK | Existing C ABI + Swift manifests + Python and ROS2 data contract tests | Released/versioned SDK, SemVer ABI compatibility tests, third-party integration sample |
| 20. Algorithm lifecycle manager | Existing subprocess worker plus deploy/stop/quarantine lifecycle with SHA-256 recheck and explicit reset | Live iOS supervisor, model restart under true device load, code-signing and OS sandbox |
| 21. Model catalog | SHA-256 content check, constrained backend selection, Swift declaration tests | Core ML/Metal/ONNX model loading with measured memory and actual performance |
| 22. Reproducible experiments | Dataset hash pinning, seeded errors, percentile and bootstrap CI, immutable report | Labeled real-device datasets and cross-GPU reproducibility campaigns |
| 23. Simulation and HIL | Deterministic replay faults, delay, duplicate, drop and source clock integrity | Physical hardware-in-the-loop and controller/firmware simulator |
| 24. Privacy and data retention | Existing AES-GCM and offline grants plus two-phase derived-record retention | iOS app-wide authorization, OS keychain integration, enforced live retention policy |
| 25. Developer diagnostics | Existing pipeline spans and metrics plus reproducible quality CLI | iOS live dashboard, thermal/power instrumentation, remote telemetry controls |
| 26. Interoperability | Strict ROS2 PoseStamped payload mapping with verified frame/time | ROS2 runtime transport, bridge QoS, external client contract tests |
| 27. Shared spatial frames | Time-bounded Swift frame-graph revisions, uncertainty and clock-domain gates | Measured head/phone/camera/body extrinsics and physical accuracy |
| 28. Evidence-based spatial memory | SQLite indexes, provenance and uncertainty-bound queries | Real-time camera localization, persistence integration and change-detection evaluation |
| 29. Predictive human interaction | Native bounded yaw/pitch look-preview, Swift facade and outlier tests | Physical headset behavioral study, human factors and target relevance validation |
| 30. Adaptive heterogeneous compute | Native hysteretic optional-quality governor with 30Hz recovery tests | Actual CPU/GPU/ANE scheduling, Core ML profiling and iPhone thermal/battery evaluation |

## Mandatory safety boundary

No P2 module grants flight or gimbal authorization. The existing bench-only
command gate and physical controller remain unchanged. No raw DJI IMU, true
camera capture timestamps, verified external calibration or actual hardware
capability is fabricated by this release.

## Evidence provenance

The portable tests are Linux C++/Swift and Python plus GitHub CI where
executed. Do not mark hardware gates passed until device-side logs, firmware
version, exact iOS/SDK version, observed p95/p99 latency and repeatable
physical results are attached.
