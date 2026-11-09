# Multimodal transport contract

AeroSpatial's data plane is a bounded C++17, in-process publish/subscribe bus.
Its independent streams are `head=1`, `telemetry=2`, `video=3`,
`perception=4`, and `diagnostic=5`. This is a transport, not a flight command bus.

## Event envelope

`ASBusHeader` carries `stream_id`, per-stream `sequence`, source monotonic
`timestamp_ns`, `clock_domain`, `kind`, `trace_id`, and `quality_flags`.
Publishers must set the sequence to zero. The bus assigns one-based sequences
only to successfully accepted publications. For each stream the clock domain
must stay constant and timestamps must not regress. Events from different
clock domains **cannot** be ordered just by comparing timestamp values.
Use the existing `ClockBridge` for explicit, uncertainty-aware alignment.

Quality flags: bit 0 valid (mandatory), bit 1 simulated, bit 2 estimated clock,
bit 3 low confidence, bit 4 stale, bit 5 observed upstream gap. Unknown flags
are rejected. Each subscriber receives an independent missed-event count,
calculated from the sequence gap after an overwrite. This gap is not
implicitly a failed sensor, and cannot be used as a flight authorization.

## Backpressure and memory

Each stream has independent bounds on retained events and payload size.
An invalid configuration that would reserve a maximum payload budget above
128 MiB per stream is rejected. Observations and encoded video use
`ASBUS_OVERWRITE_OLDEST`. Diagnostic events use `ASBUS_REJECT_NEWEST`.
The latter preserves unread events and refuses new messages, allowing an
upstream caller to log or retry **off** the time-critical callback.
It does not automatically block or retry the publisher.

Publish allocates/copies the payload once into native-owned storage. Readers
can use a bounded copy read or an internal shared-pointer lease for zero-copy
fan-out; a single outstanding lease is allowed per subscriber. Leases can
extend payload lifetime beyond the ring buffer's retained data limit, but their
number is bounded by the per-topic subscriber limit. Release immediately.
Concurrent publish and polling are synchronized by a per-topic mutex, so
this implementation is **not lock-free, wait-free, or hard real-time**.
Avoid publishing very large video frames on a control callback.

## Video and perception

A video event contains **encoded** video bytes and codec identifier in `kind`.
A frame's native capture timestamp and clock domain must be supplied by the
capture adapter. No MJPEG/H.264 parser, zero-copy CVPixelBuffer transport,
image processing, DJI video ingress or frame decoder is claimed here.
A perception event is a byte payload with a caller-defined model identifier.
Both paths have explicit memory bounds, provenance and gap accounting.
The included app currently feeds head and telemetry into the bus; live video
and perception producer adapters are extension points, not connected inputs.

## Swift and Python

`SpatialBus` and `SpatialSubscription` expose the native bus through the
Swift Package target. The app uses the same instance for accepted AirPods
head samples, simulated head samples and accepted aircraft snapshots.
`SpatialBusEnvelope` serializes transport metadata to JSONL and includes small
non-video payloads only by explicit opt-in. Binary video is omitted for
privacy and volume. Python `bus-audit` streams and validates these envelopes,
checks sequence gaps and clock domains, and aggregates O(number of streams)
metrics. It never connects to aircraft.

## Example commands

```bash
swift test
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release -DAEROSPATIAL_BUILD_BUS_BENCHMARK=ON
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
./build-native/aerospatial-bus-bench 250000
PYTHONPATH=Toolkit python3 -m aerospatial_tools bus-audit Fixtures/multimodal.jsonl
```

## Known limits

- No cross-process IPC or network transport: consumers run in one process.
- No durable message queue or exactly-once delivery guarantee.
- No hard real-time deadline guarantee; performance figures are host-specific.
- Clock translation and video timestamp calibration are independent tasks.
- Producer-side backpressure response must be explicitly implemented by each adapter.
- Future live video integration requires captured buffers, codec metadata,
  validated camera intrinsics, and an independent iOS hardware test.

## Global resource governance and lifecycle

`as_bus_set_payload_budget` configures one aggregate payload-byte cap across all
streams, **before** topics are added. `as_bus_memory_stats` reports current and
peak live payload bytes, including data kept alive by native subscriber leases.
It does not measure shared-pointer or container allocator overhead. The default
native budget is 256 MiB; the Swift application configures 64 MiB. Configure
headroom for at least one new event in addition to the retained ring contents:
an overwrite attempts to allocate the replacement before evicting an old slot.
If budget reservation fails, the existing retained event is not destroyed and
the publisher receives `ASBUS_MEMORY_BUDGET`.

`as_bus_open_publisher` returns a stable topic handle. Use `as_bus_publish_fast`
on high-frequency paths to avoid repeatedly locking the global topic table.
`as_bus_close_publisher` releases it. Multiple producer threads may publish
through one open handle. Do not concurrently free a handle while publishing.
Destroying a parent bus closes topics, while subscribers can drain retained
messages and publisher handles subsequently return `ASBUS_CLOSED`.

## Explicit time-alignment layer

`MultimodalTimeline` is a bounded Swift metadata-only nearest-neighbor matcher.
Callers must supply normalized nanosecond timestamps, uncertainty and original
clock domains when constructing `TimelinePoint`. Matching requires both a
configured maximum clock uncertainty and `abs(skew) + uncertainty <= tolerance`.
Stale samples are rejected. No payload duplication, interpolation, automatic
clock conversion, video decoding or flight actuation happens in this layer.

## Performance method

The bus microbenchmark supports `count`, `payload_bytes`, `reader_count`, and
`fast|indexed` arguments. Compare results on the same host with the same build
flags and inputs. A high event rate for 8-byte payloads is not evidence of
low latency with video frames or an iOS device.

```sh
./build-native/aerospatial-bus-bench 150000 8 0 fast
./build-native/aerospatial-bus-bench 150000 8 0 indexed
./build-native/aerospatial-bus-bench 150000 1024 4 fast
```
