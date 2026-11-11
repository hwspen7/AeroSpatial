# Source layout

Code is organized by technical responsibility, not by delivery phase. Implementation files are moved without changing their source code. Seven relocated test files update repository-root fixture lookup paths to keep CI working.

- `App/Application`, `App/ViewModels`, `App/Views`, `App/Devices`, `App/Video`, `App/Controls`, `App/Services` contain the iOS entry point and adapters. The app Info.plist stays in App/ for XcodeGen.
- `Core/Algorithms`, `Core/Devices`, `Core/Events`, `Core/Geometry`, `Core/Interop`, `Core/Safety`, `Core/Storage`, `Core/Timing`, `Core/Tracking`, `Core/Video` group Swift Package Manager sources.
- `Tests/` mirrors the functional areas of Core.
- `ToolkitTests/` separates Python regression, numerical, integration, runtime and data tests. Each child folder is an importable package so unittest discovery descends into it.

Paths deliberately kept stable in this pass: `Kernel/` and `NativeTests/` (the CMake and C++ local include contract), `Toolkit/aerospatial_tools/` (public Python module import names), `Docs/` (existing Markdown deep links), all fixtures, and the root build manifests. They can be rearranged in a later reviewed pass with explicit path migrations.

## Validation

Run `swift test`, `python -m unittest discover -s ToolkitTests -v`, and the existing GitHub Actions workflows. Physical Mavic Air 2 acceptance is separate from software CI.
