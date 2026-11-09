# Foundation audit and risk register

This register distinguishes verified fixes from pending hardware or architecture work.
Portable tests are **not** equivalent to successful flight or iOS device validation.

| Priority | Finding | Disposition | Verification |
| --- | --- | --- | --- |
| P0 | No total payload budget across topics | Fixed: configurable bus-wide cap | Native resource and concurrent allocation tests |
| P0 | Zero-copy leases extend payload lifetime | Fixed: live payload accounting includes leases | Lease overwrite and release tests |
| P0 | No end-of-stream distinction on bus shutdown | Fixed: explicit `ASBUS_CLOSED` | Parent-destroy drain tests |
| P0 | Global topic-table lock acquired for each publish | Fixed: cache publisher handles in Swift | Fast-path benchmarks and Swift tests |
| P0 | Subscriber registration allocation failure leaks handle | Fixed: exception-safe ownership | Static review and fault-path coverage limits noted |
| P0 | No concurrent global budget test | Fixed: two-topic concurrent stress | Native allocation test |
| P1 | Clock domains cannot be compared directly | Partially addressed: explicit normalized timeline | Cross-domain alignment tests |
| P1 | Clock uncertainty omitted from joins | Fixed for timeline joins | Strict skew plus uncertainty checks |
| P1 | Transport and flight command safety separation | Maintained | No bus-to-flight actuator connection |
| P1 | Protocol migration and format version policy | Pending | Versioned schema proposal required |
| P1 | Initial subscriber missed counter unvalidated | Fixed: bound first gap, preserve late-start semantics | Python tests |
| P1 | Distinguishing upstream gaps from overwritten events | Partially addressed: independent audit counters | Python provenance tests |
| P1 | Benchmarks only tested small payloads | Fixed: tunable payload and reader count | Benchmark smoke tests |
| P1 | Real video ingestion/decoded frames | Pending physical iOS/DJI integration | Hardware bench required |
| P2 | Swift encoding/copy costs in high-frequency paths | Pending binary event format and iOS profiling | Instruments required |
| P2 | Durable segmented recording/recovery | Pending | Design and corruption tests required |
| P2 | Spatial memory and perception integration | Pending model integration | Dataset and accuracy tests required |
| P2 | AirPods and Mavic Air 2 physical integration | Pending | iPhone/Mac/drone hardware required |
| P2 | Deeply nested UI module directories | Fixed: app Swift sources flattened | Swift syntax parse, macOS CI still required |
| P2 | Long-running latency and memory service levels | Pending | Soak tests and hardware performance measurements |

## Reliability constraints

- A successful publish is only an in-memory acceptance. It does not imply delivery, persistence, or flight-command execution.
- Native leases keep payloads alive until released. The global cap accounts for live payload bytes, not container/vector allocator metadata.
- During an overwrite publication, new payload allocation occurs before old slot reclamation; configure budget for at least one replacement payload of headroom. An allocation rejected by the budget must preserve the old message.
- Monotonicity is per topic and declared clock domain. The timeline only accepts **caller-normalized timestamps** and explicit uncertainty; it never implicitly treats different clocks as interchangeable.
- Fast publisher handles can outlive the parent bus and return `ASBUS_CLOSED`. Do not destroy a handle while another thread is calling through that same handle.
- Safety-critical command gating remains outside this transport. An unreliable source must never bypass explicit user authorization or the aircraft's own failsafes.
