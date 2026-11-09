# Versioned event protocol (v1)

The common offline interchange format is **UTF-8 JSON Lines**, one event per line. The JSON Schema is `Fixtures/session.schema.json`. New iOS recordings and generated Python fixtures use `schemaVersion: 1`. Older foundation logs without a version remain readable, but do not get automatic sequence integrity guarantees.

```json
{
  "schemaVersion": 1,
  "sessionId": "local-session-id",
  "sequence": 7,
  "wallTime": "2026-11-09T00:00:00Z",
  "uptime": 45678.125,
  "kind": "head",
  "source": "airpods",
  "fields": {"yaw": 10.0, "pitch": -4.0, "roll": 0.0, "sensor_uptime": 45678.118}
}
```

## Field contract

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Integer 1. Future versions require explicit decoder changes. |
| `sessionId` | Generated once for each recording. May be a UUID; no identity information required. |
| `sequence` | Contiguous integer from 0, incremented on successfully written events. |
| `wallTime` | ISO-8601 timestamp, for display only. |
| `uptime` | Monotonic seconds on the recording host. |
| `kind` | Event type, such as `head`, `telemetry`, `calibration`, `arm`, `disarm`, `gimbal_command`, `advisory`, `spatial_marker`. |
| `source` | Provenance label, such as `simulator`, `airpods`, `dji`, `app`, `advisor`. |
| `fields` | Finite numeric map with at most 128 keys, unit conventions documented per type. |
| `note` | Optional operator or system message. |

Head `yaw`, `pitch`, and `roll` and gimbal `target_pitch` use **degrees**. Latitude/longitude are decimal degrees. Altitude, when present, uses meters but may have a different vertical reference from pilot GPS. Battery fields are percentages. `head_timestamp` on a `gimbal_command` record identifies the head input used to issue a command: `command.uptime - head_timestamp` is the application sensor-to-command age, **not** the drone's motor latency. A later `gimbal_ack` record includes `command_uptime` and measures callback turnaround, also **not physical motion completion**. Every record's top-level uptime is the logger's monotonic receive/issue time; source-sample timestamps belong in `fields.sensor_uptime` to avoid false cross-stream clock regressions.

## Integrity rules

- No non-finite values, boolean-as-number values, corrupt JSON, unsupported version or oversized records. Source, kind and field identifiers are bounded ASCII tokens. Notes are capped at 4096 UTF-8 bytes.
- Session sequences must increase by exactly one. Uptime must not decrease.
- Unversioned legacy records are accepted without fabricating missing session IDs.
- `spatial_marker` records store a **fresh aircraft GPS coordinate at the time of the operator mark**. Ingest into local memory is idempotent; it never claims the video subject's location.
- Raw logs expose flight paths and locations. An opt-in `sanitize` tool creates separate privacy-reduced copies, but users must inspect custom fields before sharing. Files with `*.jsonl` and SQLite databases are ignored by Git by default, except committed fixtures.

## Reproducible integration

`Fixtures/session.jsonl` is a seeded, artificial 2-second session. Both the Swift replay CLI and Python validator accept it, and Python native parity tests compare geographic distance with the C++ probe. No real flight log or personal location is included in the fixture.

## Version 0.3 extensions without changing v1 on disk

- `EventContract` is enforced by the Swift recorder and decoder. It places bounds on fields, note size and identifier syntax.
- `SensorHealthMonitor` and `GimbalCommandGate` are in-memory safety modules and do not require a schema migration. Optional `command_timeout`, `command_blocked` and `disarm` events are ordinary v1 records.
- A new Swift virtual-time control-loop simulator emits validated v1 traces that Python can parse and audit.
- Typed frame observations live in a **separate, explicitly versioned SQLite perception table**, not silently inside the numeric-only event map. Pixel data and aircraft video are not stored by this module.
