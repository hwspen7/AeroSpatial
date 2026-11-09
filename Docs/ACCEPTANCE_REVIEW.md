# Acceptance review — software versus field readiness

This is a strict evidence register. A passed unit test is **not** a flight or
mobile device acceptance. The original P0/P1/P2 audit and the subsequent
algorithm-platform tracks have different scopes and are recorded separately.

## Original transport, data and hardware audit

| Priority | Requirement | Portable status | Remaining gate |
| --- | --- | --- | --- |
| P0 | Aggregate payload cap | Tested | Profile allocator overhead on iPhone |
| P0 | Leased payload accounting | Tested | Long-lived lease stress on mobile |
| P0 | Shutdown semantics | Tested | App lifecycle integration |
| P0 | Cached publisher handles | Tested | iOS profiling |
| P0 | Allocation failure cleanup | Tested fault hooks | Full allocator-wide failure campaign |
| P0 | Multithread pressure and benchmarks | Tested | Sustained device soak and SLO thresholds |
| P1 | Explicit source clock domains | Tested | Real device clock calibration |
| P1 | Clock uncertainty propagation | Extended and tested | Establish hardware-derived bounds |
| P1 | Flight command safety separation | Maintained | Hardware safety review |
| P1 | Versioned event schemas | Tested | External client compatibility tests |
| P1 | Initial gap audit | Tested | Capture source creation cursors in all adapters |
| P1 | Loss reason provenance | Tested offline | Instrument all live ingress paths |
| P1 | Workload-sensitive benchmarks | Tested | Real video and thermals |
| P1 | Live video | Offline decoder tested | DJI MSDK video callback, pixel buffers and device test |
| P2 | Swift high-rate copy overhead | C++ fast path implemented | CVPixelBuffer zero-copy and Instruments |
| P2 | Persistent segments and recovery | Portable tested | Retention lifecycle in live app |
| P2 | Visual memory | Image-level offline matching tested | Real camera calibration and geo-relocalization |
| P2 | AirPods and DJI compatibility | Not tested | Physical iPhone, headphones, controller, aircraft |
| P2 | Shallow directory conventions | Tested by repository layout | Maintain in reviews |
| P2 | Long-duration latency and memory | Short soak and statistics tested | 24-hour device run and thermal baseline |

## Algorithm-platform tracks

| Priority | Track | Portable capability | Remaining gate |
| --- | --- | --- | --- |
| P0 | Typed event registration | Validated | Live producer integration |
| P0 | Causal pipeline tracing | Tested | Decoder/model instrumentation |
| P0 | Optional compute admission | Native + Swift tested | Actual iPhone scheduling latency |
| P0 | Deterministic replay | Tested | Curated real capture datasets |
| P1 | Calibration registry | Validated immutable revisions | Actual optical and extrinsic calibration |
| P1 | Multimodal time alignment | Robust affine fit, bounds tested | True capture timestamps |
| P1 | Camera projection | Brown-Conrady inverse tested | Device lens parameters |
| P1 | Plugin API | Manifest planning + process isolation tested | Signed trusted deployment and OS sandbox |
| P1 | Quality evaluation | Diagnostics, gates and synthetic metrics | Labeled dataset confidence intervals |
| P1 | Spatial memory | Image feature retrieval + RANSAC tested | Geo-referencing and repeated-scene accuracy |
| P2 | Vision inference | OpenCV decoding and feature extractor tested | Live model loader, GPU benchmarking |
| P2 | Device capability negotiation | Software policy tested | Exact firmware and MSDK feature probe |
| P2 | Privacy/access controls | Default-deny export + AES-GCM tested | App-wide enforcement, key vault, retention integration |
| P2 | Reliability monitoring | Short soak + metrics tested | 24h physical workload, statistical regression gates |

## Device acceptance never substitutes

1. Xcode signed build on supported iOS, actual AirPods head-motion events,
   permission and disconnect tests.
2. DJI Mobile SDK V4 linking and Mavic Air 2 passive telemetry for the real
   controller and firmware combination.
3. Propeller-off stationary gimbal-only bench tests, deliberate authorization,
   stop behavior, and RF/latency measurement.
4. Lens intrinsics and camera/body transform calibration from physical samples.
5. Real video ingress and recorded timestamp uncertainty measurements.

**No flight-control command path is included.** Until these gates pass, this
project is a portable algorithm library and experimental app scaffold, not a
production-ready drone-control application.
