# Integration acceptance and remaining evidence

The source is a **portable software foundation**, not an aircraft-certified flight controller. A passing simulated test is never substituted for a real AirPods/iPhone/Mavic Air 2 acceptance test.

| Original finding | Implementation and test | Acceptance status |
| --- | --- | --- |
| P0 global bus payload budget | `BusBudget`, `test_bus_resources`, `test_bus_budget_race` | Software verified; allocator overhead excluded |
| P0 leased payload retention | Reference-counted budget reclamation, lease overwrite test | Software verified |
| P0 subscription shutdown | `ASBUS_CLOSED`, parent destroy/drain test | Software verified; destruction cannot race with raw parent pointer calls |
| P0 global publish index lock | Cached publisher handles, indexed/fast benchmarks | Software verified |
| P0 subscription allocation failures | Three deterministic injected failure points, handle cleanup, repaired active-subscriber reporting | Software verified |
| P0 sustained concurrent overload | Four writers and concurrent reader, bounded memory, sanitizer suite, configurable soak count | Short/medium soak verified; 24-hour hardware soak pending |
| P1 disparate clock domains | Explicit affine `ClockBridge` and `MultimodalTimeline` | Portable verified; real capture-clock calibration pending |
| P1 clock uncertainty | `ClockUncertainty`, uncertainty-aware join gating | Explicit bounds verified; no automatic end-to-end estimation yet |
| P1 observation versus actuation | Observation bus remains separate from command authorization | Architecture verified; flight control intentionally absent |
| P1 protocol evolution | Strict opt-in bus metadata version 2, legacy version 1 parsing, reject lossy downgrade | Portable verified; third-party format negotiation pending |
| P1 initial sequence gaps | Audit bounds initial missing count, does not fabricate unseen prior events | Software verified subject to subscription cursor semantics |
| P1 loss provenance | Separate upstream, subscriber, deliberate sampling, source rejection counters | Offline verified; full live-adapter accounting pending |
| P1 realistic workloads | Payload- and subscriber-configurable native benchmarks, CI smoke gate | Portable verified; device measurements pending |
| P1 video stream | `EncodedFrame`/`VideoIngress`, codec and clock-domain validation, bounded C++ video topic | Synthetic encoded frames verified; DJI decoded/encoded video ingress pending |
| P2 Swift payload serialization | Compact 44-byte CRC-checked native head record with Python parity, legacy JSON preserved | Portable verified; mobile throughput profiling pending |
| P2 segmented durable recording | Native-backed Swift segment writer and Python reader/recovery; CRC, rotation and capacity tests | Library verified; existing UI JSONL recorder not migrated |
| P2 spatial memory association | Source-checked observation/frame matching with timestamp uncertainty | Offline verified; real video/map localization pending |
| P2 physical AirPods and aircraft | Hardware checklist in `HARDWARE_TEST_PLAN.md` | **Not tested; iPhone, Mac and actual aircraft required** |
| P2 directory depth | Source directories kept shallow; only required C header/Python package nesting | Verified |
| P2 long-running observability | Bounded online latency histogram, memory and drop thresholds, native multi-producer stress | Offline verified; 24-hour iOS instrumentation pending |

## Required hardware gates

1. Compile and install the iOS application on a signed physical iPhone with Xcode. The portable Linux Swift package is insufficient.
2. Verify actual headset sensor rate, axis signs, timestamp drift, restart behavior and disconnect watchdog.
3. Validate Mavic Air 2 passive telemetry with the actual controller and firmware; no live-flight controls are shipped.
4. With propellers removed, independently verify opt-in gimbal test commands and all cancellation/interlock paths.
5. Record CPU, RSS, p95/p99 end-to-end frame latency, observed loss provenance and session recovery during at least a long-running bench soak.
6. Run a controlled reconnection and corrupted-record recovery exercise. A hardware gate must not be marked passed until measured.

## Architectural boundaries

- The transport is an in-process mutex-synchronized bus; it is **not hard real-time**, lock-free or exactly-once delivery.
- Accepted publication means only native memory acceptance, not persistence or actuator execution.
- Global budget accounts live payload bytes, not allocator internals and metadata. Configure headroom for replacement messages.
- Native leases cannot be freed concurrently with their use; clients must release them promptly.
- Video and spatial associations do not infer a photographed object's geographic location without camera calibration and depth evidence.
- The event journal uses crash-recoverable CRC-framed segments and refuses to erase old data automatically when retention is full.
