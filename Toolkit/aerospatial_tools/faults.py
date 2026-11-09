"""Deterministic offline fault injection for testing integrity and recovery paths."""

from __future__ import annotations

import json
from pathlib import Path
from .events import read_events

FAULTS = ("drop_record", "duplicate_sequence", "clock_regression", "stale_head")


def inject_fault(source: Path, destination: Path, fault: str) -> None:
    if fault not in FAULTS:
        raise ValueError(f"unsupported fault: {fault}")
    if source.resolve() == destination.resolve() or destination.exists():
        raise ValueError("fault output must be a new, separate file")
    # Decode first to refuse malformed source recordings.
    events = [json.loads(line) for line in source.read_text(encoding="utf-8").splitlines() if line.strip()]
    list(read_events(source))
    if len(events) < 4:
        raise ValueError("fault injection requires at least four records")
    index = next((i for i, row in enumerate(events) if row["kind"] == "gimbal_command"), 2)
    if fault == "drop_record":
        del events[2]
    elif fault == "duplicate_sequence":
        events[2]["sequence"] = events[1]["sequence"]
    elif fault == "clock_regression":
        events[2]["uptime"] = events[1]["uptime"] - 1
    elif fault == "stale_head":
        if events[index]["kind"] != "gimbal_command":
            raise ValueError("stale_head fault requires a gimbal_command event")
        events[index]["fields"]["head_timestamp"] = events[index]["uptime"] - 5
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("x", encoding="utf-8", newline="\n") as stream:
        for event in events:
            stream.write(json.dumps(event, sort_keys=True, allow_nan=False) + "\n")
