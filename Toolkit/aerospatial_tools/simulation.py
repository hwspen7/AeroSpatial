"""Synthetic session generator with deterministic seeded sensor dropouts."""

from __future__ import annotations

import json
import math
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path


def generate(path: Path, seconds: float = 30, seed: int = 7,
             dropout_probability: float = 0.03) -> int:
    if not math.isfinite(seconds) or not (1 <= seconds <= 3600):
        raise ValueError("seconds must be between 1 and 3600")
    if not 0 <= dropout_probability < 1:
        raise ValueError("dropout_probability must be in [0, 1)")
    rng = random.Random(seed)
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    total = int(seconds * 20)
    seq = 0
    session = f"simulated-{seed:08d}"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as file:
        def emit(kind: str, tick: int, source: str, **fields: float) -> None:
            nonlocal seq
            event = {
                "schemaVersion": 1, "sessionId": session, "sequence": seq,
                "wallTime": (start + timedelta(seconds=tick / 20)).isoformat().replace("+00:00", "Z"),
                "uptime": 1000 + tick / 20, "kind": kind, "source": source,
                "fields": {key: round(float(val), 6) for key, val in fields.items()},
            }
            file.write(json.dumps(event, sort_keys=True, allow_nan=False) + "\n")
            seq += 1

        emit("session_start", 0, "simulator")
        last_head_time = 1000.0
        for tick in range(total):
            time = tick / 20
            pitch = 14 * math.sin(0.5 * time) + rng.gauss(0, 0.15)
            if rng.random() >= dropout_probability:
                last_head_time = 1000 + time
                emit("head", tick, "simulator", pitch=pitch, yaw=20 * math.sin(time * 0.2),
                     roll=0, sensor_uptime=last_head_time)
            if tick % 4 == 0:
                emit("telemetry", tick, "simulator", battery_percent=max(0, 85 - time / 10),
                     gimbal_pitch=-30, latitude=40, longitude=-83)
            if tick % 3 == 0 and 0 <= (1000 + time - last_head_time) <= 0.4:
                # Synthetic command scheduling, not a physically executed DJI command.
                emit("gimbal_command", tick, "simulator", target_pitch=max(-85, min(0, -30 + pitch)),
                     head_timestamp=last_head_time)
        emit("session_end", total, "simulator")
    return seq
