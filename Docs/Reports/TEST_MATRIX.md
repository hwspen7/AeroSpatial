# Portable acceptance matrix (foundation 0.3.0)

| Gate | Test harness | Local result, 2026-11-09 |
| --- | --- | --- |
| C++ great-circle, dateline, numeric rejection | CMake / CTest | Passed |
| C++ WGS84 ECEF and ENU, pole/dateline cases | CMake / CTest | Passed |
| Quaternion rotation, inverse, composition and shortest-arc interpolation | CMake / CTest + Swift XCTest | Passed |
| C++ α–β filter, innovation rejection and time gaps | CMake / CTest | Passed |
| Swift FFI and calibrated coordinate-frame graph | Swift XCTest | Passed |
| Monotonic sensor health and command-ticket safety | Swift XCTest | Passed |
| Head-pitch mapping, sample freshness, advisory hysteresis, replay | Swift XCTest | Passed |
| Deterministic Swift virtual-time simulation with head dropout | Swift XCTest + Swift executable | Passed |
| Python v1 integrity and native geodesy/WGS84 parity | Python unittest | Passed |
| Python semantic audit, corruption injection and quality gates | Python unittest | Passed |
| Privacy-reduced export and digest corruption detection | Python unittest | Passed |
| SQLite spatial markers and camera-frame perception metadata | Python unittest | Passed |
| iOS Swift source syntax parsing | Linux Swift parser | Passed; **not Xcode compilation** |
| iOS SwiftUI app build | macOS / Xcode | **Not run** |
| Real AirPods motion and compass alignment | Supported physical iPhone/headphones | **Not run** |
| DJI iOS SDK linking and passive Mavic Air 2 telemetry | Supported macOS SDK/physical aircraft | **Not run** |
| DJI gimbal stop/recovery tests | Controlled propeller-off aircraft | **Not run** |
| Actual RF latency or flight acceptance | Independent measured field tests | **Not run; no flight-control commands** |

Portable results are local, not GitHub Actions evidence until the repository has been published and the workflow executes. C++ release tests use an always-on `REQUIRE()` macro rather than `assert()` so critical checks remain active with `NDEBUG`.

## Negative-case policy

Every new sensor or adapter requires stale/future/out-of-order sample tests, malformed numeric inputs, disconnect delivery, calibration/coordinate-frame validity, pending/late/failed callback handling, and operator override. Simulation is not equivalent to aircraft acceptance.
