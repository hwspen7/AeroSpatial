// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AeroSpatialCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "AeroSpatialCore", targets: ["AeroSpatialCore"]),
        .executable(name: "aerospatial-replay", targets: ["AeroSpatialReplay"]),
        .executable(name: "aerospatial-scenario", targets: ["AeroSpatialScenario"]),
        .executable(name: "aerospatial-bench", targets: ["AeroSpatialBench"])
    ],
    targets: [
        .target(name: "AeroSpatialNative", path: "Kernel", exclude: ["CMakeLists.txt", "Tools"], publicHeadersPath: "include", cxxSettings: [.headerSearchPath(".")]),
        .target(name: "AeroSpatialCore", dependencies: ["AeroSpatialNative"], path: "Core"),
        .executableTarget(name: "AeroSpatialReplay", dependencies: ["AeroSpatialCore"], path: "Replay"),
        .executableTarget(name: "AeroSpatialScenario", dependencies: ["AeroSpatialCore"], path: "Scenario"),
        .executableTarget(name: "AeroSpatialBench", dependencies: ["AeroSpatialCore"], path: "Bench"),
        .testTarget(name: "AeroSpatialCoreTests", dependencies: ["AeroSpatialCore"], path: "Tests")
    ],
    cxxLanguageStandard: .cxx17
)
