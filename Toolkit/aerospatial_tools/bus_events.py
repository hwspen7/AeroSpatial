"""Portable metadata envelope for offline multimodal bus diagnostics.

The live C++ transport is authoritative. These records intentionally omit
image/video payload bytes unless a small non-video payload is explicitly saved.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import base64
import json
from typing import Iterator

STREAM_NAMES = {1: "head", 2: "telemetry", 3: "video", 4: "perception", 5: "diagnostic"}
MAX_LINE = 32_768
MAX_SAFE_PAYLOAD = 8 * 1024 * 1024


class InvalidBusEvent(ValueError):
    pass


def unsigned(value: object, bits: int, name: str, *, positive: bool = False) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise InvalidBusEvent(f"{name} must be an unsigned integer")
    if not (int(positive) <= value <= (1 << bits) - 1):
        raise InvalidBusEvent(f"{name} out of range")
    return value


@dataclass(frozen=True)
class BusEnvelope:
    stream: int
    timestamp_ns: int
    sequence: int
    clock_domain: int
    kind: int
    trace_id: int
    quality: int
    missed: int
    payload_bytes: int

    @classmethod
    def parse(cls, raw: dict) -> "BusEnvelope":
        if not isinstance(raw, dict):
            raise InvalidBusEvent("event must be an object")
        stream = unsigned(raw.get("stream"), 32, "stream", positive=True)
        if stream not in STREAM_NAMES:
            raise InvalidBusEvent("unknown stream")
        flags = unsigned(raw.get("quality"), 32, "quality")
        if not flags & 1 or flags & ~0x3F:
            raise InvalidBusEvent("invalid quality flags")
        size = unsigned(raw.get("payloadBytes"), 32, "payloadBytes")
        if size > MAX_SAFE_PAYLOAD:
            raise InvalidBusEvent("payload length exceeds bus limit")
        payload = raw.get("payloadBase64")
        if payload is not None:
            if stream == 3 or not isinstance(payload, str) or len(payload) > 11_000:
                raise InvalidBusEvent("video payloads and oversized payloads are forbidden")
            try:
                decoded = base64.b64decode(payload, validate=True)
            except (ValueError, base64.binascii.Error) as exc:
                raise InvalidBusEvent("invalid base64 payload") from exc
            if len(decoded) != size:
                raise InvalidBusEvent("payload size mismatch")
        return cls(
            stream=stream,
            timestamp_ns=unsigned(raw.get("timestampNs"), 64, "timestampNs"),
            sequence=unsigned(raw.get("sequence"), 64, "sequence", positive=True),
            clock_domain=unsigned(raw.get("clockDomain"), 32, "clockDomain", positive=True),
            kind=unsigned(raw.get("kind"), 32, "kind"),
            trace_id=unsigned(raw.get("traceId"), 64, "traceId"),
            quality=flags,
            missed=unsigned(raw.get("missed"), 64, "missed"),
            payload_bytes=size,
        )


def read_bus_envelopes(path: Path) -> Iterator[BusEnvelope]:
    with path.open("rb") as file:
        for line_number, line in enumerate(file, 1):
            if len(line) > MAX_LINE:
                raise InvalidBusEvent(f"line {line_number}: too long")
            if not line.strip():
                continue
            try:
                raw = json.loads(line.decode("utf-8"),
                                 parse_constant=lambda value: (_ for _ in ()).throw(
                                     ValueError(f"invalid constant {value}")))
                yield BusEnvelope.parse(raw)
            except (UnicodeDecodeError, ValueError) as exc:
                raise InvalidBusEvent(f"line {line_number}: {exc}") from exc
