# Transport records and durable storage

## Compact head-motion record

The C++ ABI (`Kernel/include/aerospatial_wire.h`), Swift (`Core/Storage/CompactHeadCodec.swift`) and Python (`aerospatial_tools/Transport/wire.py`) share an **exactly 44-byte** little-endian record:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 4 | ASCII `ASHD` |
| 4 | 1 | Version 1 |
| 5 | 3 | Zero / reserved |
| 8 | 8 | UInt64 monotonic uptime in nanoseconds |
| 16 | 8 | IEEE754 yaw in degrees |
| 24 | 8 | IEEE754 pitch in degrees |
| 32 | 8 | IEEE754 roll in degrees |
| 40 | 4 | CRC32 of the preceding 40 bytes |

CRC detects accidental corruption; **it is not authentication**. Reject unknown versions, malformed timestamps, non-finite orientation and incorrect CRC. No record contains microphone or camera pixels. The legacy JSON head transport is retained for compatibility; compact encoding is opt-in via `SpatialBus.publishCompact(head:)`.

## Framed segments

Both portable implementations write `segment-00000000.bin` and sequential numbered segments. Each event is `UInt32_LE(payload_length)` + `UInt32_LE(CRC32)` + payload bytes. The writer fsyncs after append and creates a new segment at the configured size limit. On restart, the scanner validates lengths and CRC, truncates only an incomplete/corrupt *tail*, and reconstructs the index. The Python implementation fsyncs then atomically replaces its derived `index.json`. If the segment quota is full, writes stop with an explicit error rather than silently deleting flight evidence.

The Python journal supports random indexed reads. Swift currently provides a bounded writer and repair scanner; it is **not yet a replacement for the application JSONL UI recording workflow**. Every binary record has to be provided by the caller, which can use compact head telemetry or versioned JSON metadata.

## Bus metadata migration

The existing diagnostic JSON envelope remains readable without an explicit version. Version `2` adds `upstreamMissing`, `sampled`, and `rejected` event counts, plus optional `alignedNs` and `uncertaintyNs` as a **pair**. A version `1` downgrade is rejected if any such information would be lost. This format describes diagnostic metadata and is distinct from the existing versioned flight-session JSONL records.

The new provenance counters do not equate a missing observation to a lost packet: up-stream capture gaps, deliberate sampling, subscriber overwritten messages, and rejected published events are distinct categories.
