# Development guide

## Tools

- C++17 with CMake 3.16+ (Linux/macOS/MSVC Windows)
- Swift toolchain 5.9+ for the portable core (CI uses Swift 6.2)
- Python 3.10+ (offline tooling intentionally has no runtime package dependencies)
- Xcode 15+ and XcodeGen on macOS for native iOS application compilation
- Optional, separately licensed DJI MSDK iOS V4 + DJI App Key for experimental hardware integration

## Quick checks

```bash
./Scripts/run-checks.sh
```

On Windows, run `Scripts/Run-Checks.ps1` for C++ and Python. Native iOS builds are not possible on Windows. To install Python commands as console scripts, run `python -m pip install -e Toolkit` inside an isolated virtual environment.

## Modular code rules

- Each module should have a single reason to change. Aim for **fewer than 200 lines per source file**, extracting extensions, adapters, structs and independent tests instead of building monoliths.
- Source and code comments use English. Prefer precise physical units in names and API contracts.
- C++ module public functions are exported through `aerospatial_native.h` as a stable C ABI. Do not expose STL types, exceptions, raw pointers to owned memory or hardware dependencies across the Swift boundary.
- Avoid app-framework imports in the portable `AeroSpatialCore` target. SwiftUI, CoreMotion, CoreLocation and DJI APIs belong under `App` or `App`.
- Python may consume recording files, but must not become a dependency of the on-device control loop.
- A new device adapter must declare capabilities, timestamp provenance, simulator support and specific fail-closed behavior.
- Each new numerical operation needs a native test, a Swift integration test, and a Python parity case when cross-language behavior matters.
- Use `FrameGraph` for explicit transforms rather than implicit world/head assumptions, and `GimbalCommandGate` for every gimbal output path.
- Add quality rules through the explicit Python audit protocol without auto-importing executable code from recordings.
- For any publicly shared sample, use `sanitize` and manually inspect the export for custom location-like fields.

## iOS simulation compilation

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project AeroSpatial.xcodeproj -scheme AeroSpatial \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The `ios-manual.yml` workflow offers a manual GitHub-hosted macOS compile check after publishing. It is **not evidence of physical accessory or SDK operation**. When linking the optional DJI CocoaPod, generate the `.xcodeproj` before `pod install`, then open the `.xcworkspace`.

## Hardware output safety

The standard iOS binary cannot send live DJI gimbal commands. A developer experimenting with an aircraft **on a bench, without propellers, with motors stopped**, may explicitly add `AEROSPATIAL_EXPERIMENTAL_BENCH` to the Xcode target's `SWIFT_ACTIVE_COMPILATION_CONDITIONS` **for a local dedicated build only**. Do not commit that flag to `project.yml`, distribute such a build or use it in flight. The live path still requires fresh genuine AirPods samples, camera calibration, an operator confirmation, and a nonflying connected aircraft. See `HARDWARE_TEST_PLAN.md` before enabling the flag.

## Pull requests

Document the invariant being changed, include tests for invalid timestamps or inputs, include regression fixtures where applicable and state which execution environment was actually used. Do not describe an SDK interface as hardware validated without a model/firmware/Xcode/iOS evidence log.

## Reproducible scenario and release-quality checks

```bash
swift run aerospatial-scenario /tmp/swift-scenario.jsonl 5 42 2
PYTHONPATH=. python3 -m aerospatial_tools validate /tmp/swift-scenario.jsonl
PYTHONPATH=. python3 -m aerospatial_tools audit /tmp/swift-scenario.jsonl
PYTHONPATH=. python3 -m aerospatial_tools simulate /tmp/python-sim.jsonl --seconds 5 --seed 42
PYTHONPATH=. python3 -m aerospatial_tools gate /tmp/python-sim.jsonl \
  --profile Quality/simulator.json
```

The additional CLI arguments after the Swift output path specify seconds, seed and the optional dropout-start second. Neither executable connects to actual aircraft hardware.
