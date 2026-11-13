"""Versioned event parsing, with backward compatibility for legacy sessions."""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterator

MAX_LINE_BYTES = 1_000_000
MAX_NOTE_BYTES = 4096
_IDENTIFIER = re.compile(r"^[A-Za-z0-9_.:-]+$")
_ALLOWED_FIELDS = {"uptime", "kind", "source", "fields", "wallTime", "note",
                   "schemaVersion", "sessionId", "sequence"}


@dataclass(frozen=True)
class Event:
    uptime: float
    kind: str
    source: str
    fields: dict[str, float]
    wall_time: str
    session_id: str | None = None
    sequence: int | None = None
    schema_version: int | None = None


class InvalidSession(ValueError):
    """An event is malformed or violates the supported wire contract."""


def _read_event(raw: dict[str, Any]) -> Event:
    if not isinstance(raw, dict):
        raise InvalidSession("record must be a JSON object")
    if set(raw) - _ALLOWED_FIELDS:
        raise InvalidSession("unsupported event properties")
    uptime = raw.get("uptime")
    if isinstance(uptime, bool) or not isinstance(uptime, (int, float)) or \
            not math.isfinite(uptime) or uptime < 0:
        raise InvalidSession("uptime must be finite")
    for field in ("kind", "source", "wallTime"):
        if not isinstance(raw.get(field), str) or not raw[field]:
            raise InvalidSession(f"{field} must be nonempty text")
        if field != "wallTime" and (len(raw[field].encode("utf-8")) > 96 or
                                    _IDENTIFIER.fullmatch(raw[field]) is None):
            raise InvalidSession(f"{field} contains invalid characters")
    try:
        when = datetime.fromisoformat(raw["wallTime"].replace("Z", "+00:00"))
        if when.tzinfo is None:
            raise ValueError("timezone required")
    except ValueError as exc:
        raise InvalidSession("wallTime must be ISO-8601") from exc
    note = raw.get("note")
    if note is not None and (not isinstance(note, str) or len(note.encode("utf-8")) > MAX_NOTE_BYTES):
        raise InvalidSession("note exceeds 4096 bytes or is not text")
    fields = raw.get("fields", {})
    if not isinstance(fields, dict) or len(fields) > 128:
        raise InvalidSession("fields must be a bounded mapping")
    for key, value in fields.items():
        if not isinstance(key, str) or not key or len(key.encode("utf-8")) > 96 or \
                _IDENTIFIER.fullmatch(key) is None or isinstance(value, bool) or \
                not isinstance(value, (int, float)) or not math.isfinite(value):
            raise InvalidSession("fields require finite numeric values")
    version = raw.get("schemaVersion")
    session = raw.get("sessionId")
    sequence = raw.get("sequence")
    if version is not None:
        if version != 1 or isinstance(version, bool):
            raise InvalidSession("unsupported schemaVersion")
        if not isinstance(session, str) or not session or len(session.encode("utf-8")) > 128 or \
                _IDENTIFIER.fullmatch(session) is None:
            raise InvalidSession("versioned record missing sessionId")
        if isinstance(sequence, bool) or not isinstance(sequence, int) or sequence < 0:
            raise InvalidSession("versioned record missing valid sequence")
    elif session is not None or sequence is not None:
        raise InvalidSession("unversioned record cannot use sequence/sessionId")
    return Event(float(uptime), raw["kind"], raw["source"],
                 {key: float(value) for key, value in fields.items()},
                 raw["wallTime"], session, sequence, version)


def read_events(path: Path) -> Iterator[Event]:
    with path.open("rb") as stream:
        number = 0
        while True:
            line = stream.readline(MAX_LINE_BYTES + 1)
            if not line:
                break
            number += 1
            if len(line) > MAX_LINE_BYTES:
                raise InvalidSession(f"line {number}: exceeds {MAX_LINE_BYTES} bytes")
            if not line.strip():
                continue
            try:
                raw = json.loads(line.decode("utf-8"), parse_constant=lambda v: (_ for _ in ()).throw(
                    ValueError(f"invalid numeric constant: {v}")))
                yield _read_event(raw)
            except (UnicodeDecodeError, ValueError, TypeError) as exc:
                raise InvalidSession(f"line {number}: {exc}") from exc
