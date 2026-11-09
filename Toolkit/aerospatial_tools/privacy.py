"""Opt-in privacy-reduced export; raw logs are never overwritten."""

from __future__ import annotations

import json
import os
import re
import secrets
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from .events import read_events
from .validation import validate

_START = datetime(2000, 1, 1, tzinfo=timezone.utc)
_COORDINATE_FIELD = re.compile(
    r"(?:^|_)(?:latitude|longitude|lat|lon|gps|northing|easting|ecef|utm)(?:_|$)"
)
_TIME_FIELD = re.compile(r"(?:timestamp|uptime)$")


def redact_session(source: Path, destination: Path) -> int:
    """Remove known GPS fields, notes, real wall time and original session IDs.

    Numeric unknown custom fields may still encode sensitive information.
    Output is intended for opt-in sharing only after human review.
    """
    if source.resolve() == destination.resolve():
        raise ValueError("input and output paths must differ")
    if destination.exists():
        raise FileExistsError(f"refusing to overwrite: {destination}")
    if validate(source).issue_count:
        raise ValueError("source recording fails sequence/timestamp integrity validation")
    events = list(read_events(source))
    if not events:
        raise ValueError("source recording is empty")
    anchor = events[0].uptime
    if events[-1].uptime - anchor > 366 * 24 * 3600:
        raise ValueError("recording duration exceeds supported privacy export bounds")
    ids: dict[str, str] = {}
    counters: dict[str, int] = {}
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="\n",
                                         dir=destination.parent, delete=False) as stream:
            temporary = Path(stream.name)
            for item in events:
                source_id = item.session_id or "legacy"
                if source_id not in ids:
                    ids[source_id] = "anon-" + secrets.token_hex(12)
                    counters[source_id] = 0
                elapsed = item.uptime - anchor
                fields = {
                    name: round(value - anchor, 6) if _TIME_FIELD.search(name)
                    else value
                    for name, value in item.fields.items()
                    if not _COORDINATE_FIELD.search(name)
                }
                record = {
                    "schemaVersion": 1, "sessionId": ids[source_id],
                    "sequence": counters[source_id], "uptime": round(elapsed, 6),
                    "wallTime": (_START + timedelta(seconds=elapsed)).isoformat().replace("+00:00", "Z"),
                    "kind": item.kind, "source": item.source, "fields": fields,
                }
                stream.write(json.dumps(record, sort_keys=True, allow_nan=False) + "\n")
                counters[source_id] += 1
        # Exclusive creation is essential: never clobber another recording on a race.
        with destination.open("xb") as final, temporary.open("rb") as input_stream:
            for chunk in iter(lambda: input_stream.read(1024 * 1024), b""):
                final.write(chunk)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return len(events)
