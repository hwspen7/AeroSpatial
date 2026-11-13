# AeroSpatial source layout

All tracked files use at most **two directory levels below the repository root**.
Files are grouped by responsibility rather than by delivery phase.

## Major folders

- `App/<Area>/`: SwiftUI application, models, device adapters, controls and video.
- `Core/<Area>/`: portable Swift contracts, native interop, geometry, timing, safety, storage and algorithms.
- `Tests/<Area>/`: portable Swift tests. Tests that locate root fixtures must account for their two-level source directory.
- `Kernel/<Area>/`: native C++ source in `Bus`, `Geometry`, `Estimation`, `Runtime` and `Video`. `Kernel/Tools/` contains benchmarking and probe executables.
- `Kernel/include/`: the stable public C ABI headers. This folder intentionally retains all 15 public headers so the Swift/C++ integration ABI does not change.
- `NativeTests/<Area>/`: C++ tests with `Common/` for the shared test header.
- `aerospatial_tools/<Area>/`: offline Python implementation, split into bounded functional groups. `aerospatial_tools/__init__.py` extends Python's module search path to these bundled subpackages so existing imports such as `aerospatial_tools.cli`, `aerospatial_tools.frames`, and `aerospatial_tools.evidence_pipeline` still resolve.
- `ToolkitTests/<Area>/`: recursive Python unittest packages grouped by domain.
- `Docs/<Area>/`: architecture, development, validation, safety and reports, with related relative links updated.
- `Fixtures/`: stable recorded and synthetic test input files.
- `Scripts/`: cross-platform test scripts and layout verification.

## Build contracts

- `Package.swift` defines the Swift and C++ targets; `Kernel/CMakeLists.txt` enumerates native source and test paths.
- `pyproject.toml` is the installable Python project's build definition. Install with `python -m pip install -e .` or an extras group such as `'.[vision,privacy]'`.
- `PYTHONPATH=.` makes the Python tooling available from the repository root without installation.
- `python Scripts/check-layout.py` checks depth, folder size and dynamic C++ source/test registration. See [native runtime quality](Development/NATIVE_QUALITY.md) for budget, clock, ABI, Fuzzing, TSAN, latency and estimator contracts.
- GitHub Actions runs Swift, C++, Python, iOS Simulator and DJI SDK build checks. Software CI cannot substitute for AirPods and Mavic Air 2 hardware acceptance.

Do not create nested third-level folders or scatter files back into large flat source directories. Public ABI headers and import paths should only change through a separate compatibility-reviewed migration.
