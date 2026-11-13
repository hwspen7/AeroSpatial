# Portable verification record

Verified on Linux with Swift 6.2, CMake and Python 3.13 on November 9, 2026.

- Swift package: 67 tests passed, zero failures.
- C++ standalone CTest: 7 tests passed, zero failures.
- Python unittest: 30 tests passed, zero failures, three optional dependency skips.
- Full portable `Scripts/run-checks.sh`: exit status 0.
- iOS application source: Swift frontend syntax parse passed, **not** an Xcode iOS build.

Representative local Release-mode microbenchmarks, **not** aircraft or mobile measurements:

| Operation | Workload | Throughput | Notes |
| --- | ---: | ---: | --- |
| Native WGS84 batch | 500,000 points | ~30.5 million points/s | Linux host, single run |
| Swift ring insert and lookup | 100,000 samples | ~6.36 million samples/s | Linux host, single run |
| Offline event-aware sampler | 100,000 observations | ~1.44 million observations/s | Median of 5 runs |

These numbers vary with CPU, compiler and thermal conditions. No fixed speedup is claimed without a matched baseline. Real-time DJI SDK integration and AirPods hardware acceptance remain unverified.
