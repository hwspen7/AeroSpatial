# Performance design and measurement

The mobile application has two deliberately different work classes.

- Safety and command interlocks are synchronous and never delegated to a backpressure filter. Command admission is separately fail-closed, propeller-removed bench only.
- Analytics, visualization, spatial memory, diagnostic reporting and optional sample recording may be rate-limited or downsampled to protect responsiveness and memory.

## Bounded storage and lookup

`TimestampRing` preallocates a capacity-limited array and replaces overwritten entries in constant time. It queries ordered monotonic timestamps using lower/upper-bound searches with logarithmic lookup complexity. Ring head wrap and timestamp-equality corner cases are covered by tests against an independent array-based reference.

## Native bulk operators

`as_wgs84_ecef_batch` converts N valid geodetic samples. It validates the entire array prior to writing outputs. No per-sample heap allocations are performed. Input/output buffers must not overlap; malformed coordinates return a failure status without partial writes.

`as_lowpass_batch` uses a stateful scalar low-pass operation, supports in-place buffers, and rejects invalid values before modifying the buffer. The Swift facade provides array-bound checking and type conversion. The kernels are intended for offline or background bulk processing, not inside device command completion callbacks.

## Observation delivery under pressure

`StreamGovernor` can lower nonessential UI-update frequency when measured processing cost rises, with bounded intervals and important-event override. `EventAwareSampler` retains explicit critical events and significant changes while dropping redundant steady-state measurements. No data is silently removed from the aircraft control loop.

## Benchmarks

Run from the repository root:

```bash
swift run -c release aerospatial-bench 100000
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release -DAEROSPATIAL_BUILD_BENCHMARKS=ON
cmake --build build-native --parallel
./build-native/aerospatial-bench 500000
PYTHONPATH=Toolkit python3 -m aerospatial_tools benchmark --count 100000 --iterations 5
```

Report compiler, CPU, OS, sample count, warm-up, repetitions and distribution of runtimes before comparing revisions. The examples currently report a wall-time rate, not a measured hardware latency or speedup against a matched baseline. No universal samples/second threshold is enforced in CI because runner hardware varies. CI verifies correctness and runs benchmark smoke tests.

## Safety and accuracy caveats

Coordinate conversion assumes WGS84 geodetic positions with *ellipsoidal* heights, which must never be silently conflated with a DJI relative flight altitude. `ClockBridge` only estimates drift and offset from good paired samples. It is not a precise clock synchronization protocol and it must not expand the command gate's allowed staleness. The current SDK adapter is not flight validated.
