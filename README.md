# AeroSpatial

**An extensible spatial intelligence foundation for drones, wearable motion sensing, and human-in-the-loop interaction.**

![Swift](https://img.shields.io/badge/Swift-6%20%2F%205.9%2B-F05138?logo=swift&logoColor=white)
![C++](https://img.shields.io/badge/C%2B%2B-17-00599C?logo=cplusplus&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-17%2B-111827?logo=apple)
![Tests](https://img.shields.io/badge/Portable_Tests-Verified-16A34A)
![Safety](https://img.shields.io/badge/Flight_Commands-Not_Implemented-16A34A)
![License](https://img.shields.io/badge/License-MIT-8B5CF6)

AeroSpatial provides the **reusable engineering substrate** for a drone interaction system built around compatible AirPods, an iPhone, and a DJI Mavic Air 2. Its fundamental unit is not a camera gesture or a tracking feature. It is a **timestamped spatial observation**, consumed by independent geometry, motion, telemetry, awareness, safety, logging, and replay modules.

The foundation combines three languages deliberately:

- **Swift** runs the iOS application and safety-oriented state machines, adapts hardware inputs, aligns timestamps, manages operator interactions, and defines the portable application-facing APIs.
- **C++17** implements deterministic, platform-neutral numerical primitives behind a stable C interface. Its source builds both through Swift Package Manager and standalone CMake, without DJI dependencies.
- **Python** provides offline log verification, reproducible scenarios, diagnostic metrics, cross-language parity checks, and an opt-in local SQLite spatial observation store.

> **Developer preview / ongoing foundation development.** Core Swift+C++ tests, C++ tests, and Python offline tests have been executed in a Linux environment. The iOS application has been **syntax-parsed only**, not compiled or run with Xcode. No actual AirPods stream, DJI SDK binary, Mavic Air 2 connection, or aircraft command has been validated here. Real gimbal actuation is **disabled in the standard build**. See [hardware acceptance](Docs/HARDWARE_TEST_PLAN.md).

## Architecture

```mermaid
flowchart TD
    subgraph Devices[Device sources]
        AP[Compatible AirPods motion]
        PH[iPhone heading and location]
        DJI[DJI Mavic Air 2 - unverified adapter]
        SIM[Built-in simulator]
    end
    AP --> Swift[Swift sensor adapters]
    PH --> Swift
    DJI --> Swift
    SIM --> Swift
    Swift --> Health[Stream quality and watchdog]
    Health --> Sync[Monotonic time synchronization]
    Sync --> Frames[C++ WGS84 / quaternion / frame transforms]
    Frames --> Graph[Swift calibrated frame graph]
    Sync --> Tracking[Bounded pitch controller]
    Tracking --> Gate[Command ticket / callback timeout / fail closed]
    Gate -.->|Simulator or opted-in bench only| DJI
    Sync --> Recording[(Versioned JSONL sessions)]
    Graph --> Awareness[Orientation and awareness]
    Awareness --> UI[SwiftUI / speech alerts]
    Recording --> QA[Python integrity / semantic audit / quality gates]
    QA --> Privacy[Explicit privacy-reduced export]
    Recording --> Replay[Deterministic Swift replay and control scenarios]
    QA --> Memory[(Local SQLite memory)]
```

Swift owns device control and consent. C++ owns deterministic numerical operations and exposes a C ABI. Python is offline only. The portable core and its simulation tests do not depend on DJI SDK binaries or Apple frameworks.

## Implemented foundation

| Area | Implemented | Verification / boundary |
| --- | --- | --- |
| C++ spatial kernel | Great-circle geodesy, WGS84 ECEF/ENU, quaternion composition/inversion/SLERP, stereo balance, α–β filter | Standalone CMake, Swift FFI and independent Python numerical parity |
| Swift sensor pipeline | Timestamped samples, bounded alignment, wrap-aware interpolation and missing/future/out-of-order/stream-gap diagnostics | Linux Swift unit tests and iOS source integration |
| Head-to-gimbal mapping | Dead zone, explicit calibration, smoothing, rate ceiling, stale-sample interlocks and single-in-flight command tickets | Explicit fail-closed acknowledgment timeout, generation IDs and regression tests; **real output build-gated** |
| Head-relative bearing | Explicit phone/head alignment, compass-quality and time validity gates | 2D stereo-balance **preview only**; not HRTF sound |
| Passive advisor | One-shot link loss, low-battery thresholds, telemetry-age warning | Does not estimate return-to-home safety or issue commands |
| Device capabilities | Separate simulator and conservative unverified DJI profiles | No assumption that a mechanical axis is SDK controllable |
| Versioned event protocol | Bounded v1 contract, validated sequence/fields/notes, monotonic uptime and provenance | Cross-language fixtures, recorder enforcement and legacy compatibility |
| Replay | JSONL parse/integrity report and bounded, seekable virtual timeline | Offline Swift tests and Python validation |
| Synthetic sessions | Seeded Python streams plus a Swift virtual-time runner exercising the real head-pitch controller and command gate | Cross-language valid/invalid replay scenarios |
| Spatial memory | Local SQLite markers, nearby search, idempotent JSONL import | Aircraft camera location only, **not inferred object position** |
| iOS UI | Modular SwiftUI views, stream-quality counters, pending-command state, simulation and optional recording | **Not compiled with Xcode in this environment** |
| DJI MSDK V4 | Experimental telemetry and pitch adapter source, live disconnection delivery and callback interlocks | **Unverified**, requires real SDK, Mac and bench acceptance |
| Calibrated frame graph | Explicit directed/inverse rigid transforms, path resolution, no invented frame relationships | Rotation composition, inverse and graph consistency tests |
| Frame-level perception evidence | Normalized camera-image bounding boxes, confidence and model provenance in a separate SQLite schema | Offline metadata only; **no video ingestion or detector is claimed** |
| Offline quality and privacy | Declarative quality gates, semantic audit rules, seeded corruption injection, SHA-256 manifests and privacy-reduced exports | Python tests and CLI acceptance; the digest is not a digital signature |

### Deliberately not claimed

AeroSpatial does **not** currently implement live drone video decoding, visual object recognition, SLAM, HRTF 3D audio, autonomous navigation, aircraft yaw/roll control, or any flight mission. Those require independent hardware and algorithm acceptance gates. Current “head-relative audio” is a calculated **stereo pan / spoken-direction preview**; AirPods head motion is not eye tracking or a true-north heading sensor.

## Repository layout

```text
AeroSpatial/
├── Core/              # Swift algorithms, state machines and sensor fusion
├── Kernel/            # C++ numerical kernel, C ABI, CMake and microbenchmarks
├── App/               # iOS services and SwiftUI (at most two levels deep)
├── Toolkit/           # Offline data, memory, analysis and replay utilities
├── Tests/             # Swift portable tests
├── NativeTests/       # C++ numerical tests
├── ToolkitTests/      # Offline and cross-language validation
├── Bench/             # Reproducible Swift benchmarking CLI
├── Replay/            # Swift replay CLI
├── Scenario/          # Swift virtual-time scenario CLI
├── Fixtures/          # Stable event schema and sample recording
├── Quality/           # Quality thresholds
├── Docs/              # Detailed design and hardware acceptance
├── Scripts/           # Cross-platform checks
├── .github/workflows/ # Automated Linux, Windows and manual macOS builds
├── Package.swift      # Swift Package Manager using custom shallow paths
├── project.yml        # XcodeGen app definition
└── Podfile            # Opt-in DJI SDK dependency; not redistributed
```

The folders are named by **responsibility**, not programming language. No generated build files or version-numbered source filenames are tracked.

## Run the foundation without an aircraft

**On macOS or Linux, with Swift 5.9+, CMake 3.16+, a C++17 compiler and Python 3.10+:**

```bash
./Scripts/run-checks.sh
```

Alternatively, run each subsystem independently:

```bash
# Swift and the embedded C++ kernel
swift test
swift run aerospatial-replay Fixtures/session.jsonl

# Pure C++ release build
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure

# Python without any third-party runtime dependencies
PYTHONPATH=Toolkit python3 -m unittest discover -s ToolkitTests -v
PYTHONPATH=Toolkit python3 -m aerospatial_tools simulate /tmp/sample-flight.jsonl --seconds 30 --seed 7
PYTHONPATH=Toolkit python3 -m aerospatial_tools report /tmp/sample-flight.jsonl
PYTHONPATH=Toolkit python3 -m aerospatial_tools audit /tmp/sample-flight.jsonl
PYTHONPATH=Toolkit python3 -m aerospatial_tools gate /tmp/sample-flight.jsonl \
  --profile Quality/simulator.json
swift run aerospatial-scenario /tmp/swift-loop.jsonl 5 42 2
PYTHONPATH=Toolkit python3 -m aerospatial_tools validate /tmp/swift-loop.jsonl
```

For Windows, `Scripts/Run-Checks.ps1` runs the **C++ and Python** suites. The native Swift package is supported on Linux/macOS; compiling the iOS app requires a Mac.

### Local spatial observation memory

```bash
# Data stays in a local SQLite file. No cloud account required.
PYTHONPATH=Toolkit python3 -m aerospatial_tools memory add \
  --db local-memory.sqlite3 --lat 40.0 --lon -83.0 \
  --label "Camera observation point"

PYTHONPATH=Toolkit python3 -m aerospatial_tools memory nearby \
  --db local-memory.sqlite3 --lat 40.0 --lon -83.0 --radius 200

PYTHONPATH=Toolkit python3 -m aerospatial_tools memory import \
  --db local-memory.sqlite3 --session Fixtures/session.jsonl
```

Import is idempotent for versioned `spatial_marker` events. The marker represents the **aircraft GPS location at the time of the operator action**, not the distant subject in the camera view. Explicit landmark geolocation will require camera calibration, ranging, geometry and uncertainty estimates in a future module.

### Privacy-reduced export and fault regression

```bash
# Sharing is explicit. Original GPS-bearing session is never overwritten.
PYTHONPATH=Toolkit python3 -m aerospatial_tools sanitize /tmp/sample-flight.jsonl /tmp/share.jsonl
PYTHONPATH=Toolkit python3 -m aerospatial_tools digest create /tmp/share.jsonl /tmp/share.sha256.json
PYTHONPATH=Toolkit python3 -m aerospatial_tools digest verify /tmp/share.jsonl /tmp/share.sha256.json

# Test that integrity and quality checks reject damaged traces.
PYTHONPATH=Toolkit python3 -m aerospatial_tools inject-fault \
  /tmp/sample-flight.jsonl /tmp/stale-head.jsonl --fault stale_head
PYTHONPATH=Toolkit python3 -m aerospatial_tools audit /tmp/stale-head.jsonl
```

The sanitization pass strips recognized GPS-coordinate keys, notes, identifying session IDs and original wall times. It **cannot guarantee** that custom numeric fields are non-identifying. Inspect any exported data before publishing. See [data governance](Docs/DATA_GOVERNANCE.md).

### A typed foundation for future computer vision

The optional Python `PerceptionStore` records validated `FrameObservation` metadata: model ID, session/frame reference, capture uptime, normalized image bounding box and a bounded confidence score. This **does not run object detection** and does **not claim a target's geographic position**. It is an extension point for a future on-device or offline perception pipeline.

```python
from pathlib import Path
from aerospatial_tools.perception_models import FrameObservation, ImageBox
from aerospatial_tools.perception_store import PerceptionStore

frame = FrameObservation.create("session-001", "frame-1", 100.0, "example-model",
                                "vehicle", 0.92, ImageBox(0.1, 0.2, 0.3, 0.4))
with PerceptionStore(Path("observations.sqlite3")) as store:
    store.add(frame)
    print(store.by_session("session-001"))
```

## iOS app / simulation

1. On **macOS**, install Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run `xcodegen generate` in the repository root.
2. Open `AeroSpatial.xcodeproj`, choose a signing team and set your own bundle identifier.
3. Build the app in **Simulation** mode on the iOS simulator or physical iPhone. This mode does not need DJI SDK or credentials.
4. Use the demo head sliders, calibrate, and enable simulated pitch assistance. To export JSONL, enable recording before interacting.
5. On a physical iPhone, optional supported AirPods head motion and phone location/heading can be tried separately, subject to device permission and compatibility.

### DJI adapter: experimental, off by default

DJI Mavic Air 2 is a DJI Mobile SDK V4 family device, but current iOS/Xcode/firmware compatibility is **not independently established** by these source files. To try linking it, provide your own DJI developer App Key and CocoaPods dependencies and open the generated `.xcworkspace`. **The normal build never transmits gimbal pitch commands**. A dedicated compile-time flag `AEROSPATIAL_EXPERIMENTAL_BENCH` is reserved for a supervised **propeller-removed, nonflying** hardware bench experiment and must not be enabled in a shipping build. Follow every gate in [the hardware plan](Docs/HARDWARE_TEST_PLAN.md). Do not use the bench build in flight.

The included `DJIAdapter.swift` is unverified integration code, not a certification that an Mavic Air 2 firmware version permits all camera axes or accepts the current SDK signatures. Aircraft flight commands are absent.

## Engineering rules

- **Fail closed:** unauthorized, disconnected, uncalibrated, stale or malformed motion produces no new camera command.
- **Data provenance:** simulator output is never labeled physical telemetry. Heading must be true-north and of known quality before creating head/world alignment.
- **Portable computation:** numeric algorithms have explicit units and a stable C ABI. Swift owns real-time state and adapters; Python is offline.
- **Reproducible testing:** record a session, validate it, seek it with `ReplayCursor`, and compare results against fixed scenarios.
- **Local-only by default:** raw recordings can contain sensitive GPS coordinates and must not be committed or shared without review. The foundation includes an explicit privacy-reduced export; neither flight audio nor onboard video is uploaded by the tools.
- **Small files / narrow responsibilities:** new modules should normally stay under ~200 source lines, with separate tests for geometry, timing, controls, diagnostics and storage.

See [architecture](Docs/ARCHITECTURE.md), [extension interfaces](Docs/EXTENDING.md), [coordinate frames](Docs/SPATIAL_FRAMES.md), [command safety](Docs/COMMAND_SAFETY.md), [quality gates](Docs/QUALITY_GATES.md), [data governance](Docs/DATA_GOVERNANCE.md), [event protocol](Docs/EVENT_PROTOCOL.md), [test matrix](Docs/TEST_MATRIX.md) and [roadmap](Docs/ROADMAP.md).

## Independent project

AeroSpatial is an independent open-source research/development foundation and is not affiliated with or endorsed by Apple or DJI. Apple SDKs and DJI's Mobile SDK are provided under their separate terms, and the DJI binary SDK is **not bundled** in this repository.

Original project code is MIT-licensed. See [LICENSE](LICENSE).

## Performance-oriented foundation

AeroSpatial separates **fast, deterministic computation** from device callbacks and offline experimentation.

- `TimestampRing` is a bounded, preallocated ring. Appends do not shift memory (`O(1)`); timestamp lookup uses binary search (`O(log N)`). It replaces the earlier front-removal and linear scanning implementation.
- `NativeBatch` binds C++ allocation-free WGS84 and low-pass array kernels to Swift; invalid inputs are rejected before the output is modified.
- `StreamGovernor` controls **only** telemetry visualization or analytics publishing rate, with backoff under load. It must never gate safety checks or control admission.
- `ClockBridge` estimates bounded remote-to-local clock drift for observation alignment with explicit outlier rejection. It does not certify synchronized clocks or authorize a hardware command.
- The offline toolkit offers an event-aware sampler and constant-memory online moments. Important observations can bypass downsampling.

Run repeatable microbenchmarks (hardware dependent, not a flight latency guarantee):

```bash
swift run -c release aerospatial-bench 100000
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release -DAEROSPATIAL_BUILD_BENCHMARKS=ON
cmake --build build-native --parallel
./build-native/aerospatial-bench 500000
PYTHONPATH=Toolkit python3 -m aerospatial_tools benchmark --count 100000 --iterations 5
```

See [performance contract and measurement methodology](Docs/PERFORMANCE.md).
