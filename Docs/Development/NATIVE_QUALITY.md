# Native runtime quality and verification

All C++ components are observation-only: no aircraft authorization, flight actuation,
timestamp calibration or decoder hardware attestation is provided.

## P0: shared resource budget

`ASResourceGovernor` provides a thread-safe, aggregate payload-byte budget.
The opt-in constructors `as_bus_create_budgeted`,
`as_memory_pool_create_budgeted` and `as_work_queue_create_budgeted` charge
the same governor for retained events, immutable pool leases, queued work
and popped work leases. Use `as_resource_permit_acquire` with
`AS_RESOURCE_VIDEO` to account for registered downstream video buffers.
Permit ownership survives producer and governor destruction; release occurs
only after the last consumer lease. Unregistered VideoToolbox textures and
allocator bookkeeping are not charged. Legacy unbudgeted constructors
remain supported but do not participate in shared enforcement.

## P0: cross-device clock quality

`ASClockQuality` independently validates AirPods, iPhone and aircraft
timestamp domains. Callers must supply an independently established mapping
of source time into one reference monotonic clock, reference arrival time
and uncertainty. Stale, future, regressing, uncertain and discontinuous
observations are rejected without advancing the accepted anchor. Reconnect
requires explicit domain reset. This is not offset estimation or clock
calibration.

## P0: C ABI compatibility

`as_native_abi_info` advertises ABI version 1.1, structure size and feature
bits without altering existing C ABI layouts. Consumers should reject an
unsupported major version or missing feature before calling extensions.

## P1: fuzzing, races and performance

`LLVMFuzzerTestOneInput` exercises H.264 NAL parsing, H.264 access-unit
assembly, callback boundary splits, wire CRC and valid record round trips.
Clang libFuzzer runs under ASan/UBSan with a seeded real H.264 fixture.
A deterministic standalone smoke runner also checks malformed inputs.

ThreadSanitizer instruments the bus, memory, executor, work queue and global
governor concurrency regression targets. Race reports fail CI; they are
not ignored or converted into a successful skipped job.

`ASPipelineMetrics` collects ingress, queue, decode, algorithm and
end-to-end durations, counts, deadline breaches and logarithmic p95/p99
upper bounds. Pairs of timestamps MUST be in the same monotonic domain.

## P2: estimator consistency

`as_inertial_covariance_quality` checks symmetry, finiteness, quaternion
normalization and strictly positive Cholesky covariance factorization.
`as_inertial_position_nees` computes full 3D normalized estimation error
against independently supplied ground-truth ENU coordinates. Regression
tests cover repeated inertial prediction, position updates and invalid
covariance injection. Real-world drift and consistency cannot be claimed
without labeled device data and noise calibration.

## Leak and soak tests

The soak executable repeatedly exercises full bus/pool/queue/governor
lifecycles, enforcing zero outstanding accounted bytes and stable bounded
high-water usage. ASan independently checks native leaks. The duration
is a CI regression workload, not a 24-hour iPhone thermal acceptance.

## Commands

```bash
python Scripts/check-layout.py
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Debug \
  -DAEROSPATIAL_BUILD_FUZZ_SMOKE=ON -DAEROSPATIAL_BUILD_SOAK=ON
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
./build-native/aerospatial-fuzz-smoke
./build-native/aerospatial-soak 200000
```

The Foundation CI independently runs libFuzzer, TSAN, ASan/UBSan,
long-run soak, native Windows tests, and Swift/Python bridge tests.
The separate iOS simulator and DJI SDK workflows must pass for the same
commit before software acceptance.

## Dynamic build registration

`Kernel/CMakeLists.txt` uses CMake `file(GLOB ... CONFIGURE_DEPENDS)`
to discover approved native C++ source and test directories.
`Scripts/check-layout.py` checks all source directories, test naming,
every tool registration, import compatibility and repository depth.
No source/test counts are hardcoded. New source files are automatically
compiled and new test files are automatically registered.
