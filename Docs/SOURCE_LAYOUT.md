# Source layout

Code is organized by technical responsibility, not by delivery phase. Implementation files are moved without changing their source code. Seven relocated test files update repository-root fixture lookup paths to keep CI working.

- `App/Application`, `App/ViewModels`, `App/Views`, `App/Devices`, `App/Video`, `App/Controls`, `App/Services` contain the iOS entry point and adapters. The app Info.plist stays in App/ for XcodeGen.
- `Core/Algorithms`, `Core/Devices`, `Core/Events`, `Core/Geometry`, `Core/Interop`, `Core/Safety`, `Core/Storage`, `Core/Timing`, `Core/Tracking`, `Core/Video` group Swift Package Manager sources.
- `Tests/` mirrors the functional areas of Core.
- `ToolkitTests/` separates Python regression, numerical, integration, runtime and data tests. Each child folder is an importable package so unittest discovery descends into it.

- `Kernel/src/` separates C++ native bus, geometry, estimation, runtime and video implementation. `Kernel/Tools/` contains probe and benchmarking executables. `Kernel/include/` preserves the stable public C ABI headers.
- `NativeTests/` groups C++ native tests by subsystem and keeps the shared assertion header in `NativeTests/Common/`. CMake maps each test to its new source location.
- `Package.swift` excludes `Kernel/Tools/` and explicitly adds the native target root to header search paths to preserve legacy `#include "include/..."` directives after relocation. CMake configures the equivalent private include paths.
- Paths deliberately kept stable: `Toolkit/aerospatial_tools/` (public Python module names), `Docs/` (Markdown deep links), all fixtures, and the root build manifests.


## Validation

Run `swift test`, `python -m unittest discover -s ToolkitTests -v`, and the existing GitHub Actions workflows. Physical Mavic Air 2 acceptance is separate from software CI.
