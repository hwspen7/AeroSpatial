# Transport records and durable storage

## Compact head-motion record

The C++ ABI (`Kernel/include/aerospatial_wire.h`), Swift (`Core/CompactHeadCodec.swift`) and Python (`Toolkit/aerospatial_tools/wire.py`) share an **exactly 44-byte** little-endian record:

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

## Application recording integration

The iOS `SessionRecorder` now uses a bounded `SegmentJournalSink`, rather than
writing every JSONL record synchronously on the main actor. The queue stores
versioned JSON session objects as CRC-framed binary records, rotates segments,
fsyncs admitted records, and preserves older sessions until explicit user action.
Recording failure is surfaced when the next event is submitted or the queue is
flushed. The app's export target is now a session **directory**, not a JSONL file.
To create a portable JSONL file, copy the session folder and run:

```sh
PYTHONPATH=Toolkit python -m aerospatial_tools journal-export flight-directory exported.jsonl
PYTHONPATH=Toolkit python -m aerospatial_tools validate exported.jsonl
```

This conversion is an explicit action and refuses overwriting existing files.
A directory is not a single video or archive; use a file-manager export on iOS.
