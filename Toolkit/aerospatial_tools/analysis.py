"""Offline metrics. Sensor-to-command age is NOT a measured radio/gimbal latency."""

from __future__ import annotations

import math
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from statistics import mean
from .events import read_events


@dataclass(frozen=True)
class SessionMetrics:
    head_samples: int
    telemetry_samples: int
    gimbal_commands: int
    first_battery_percent: float | None
    last_battery_percent: float | None
    sensor_to_command_age_ms_p50: float | None
    sensor_to_command_age_ms_p95: float | None
    command_to_callback_ms_p50: float | None
    command_to_callback_ms_p95: float | None
    event_sources: dict[str, int]

    def as_dict(self) -> dict:
        return asdict(self)


def percentile(values: list[float], percent: float) -> float | None:
    if not values:
        return None
    points = sorted(values)
    index = (len(points) - 1) * percent / 100
    low, high = math.floor(index), math.ceil(index)
    return points[low] * (high - index) + points[high] * (index - low)


def analyze(path: Path) -> SessionMetrics:
    source_counts: Counter[str] = Counter()
    head = telemetry = gimbal = 0
    first_battery = last_battery = None
    ages: list[float] = []
    callbacks: list[float] = []
    for event in read_events(path):
        source_counts[event.source] += 1
        if event.kind == "head":
            head += 1
        elif event.kind == "telemetry":
            telemetry += 1
            if "battery_percent" in event.fields:
                if first_battery is None:
                    first_battery = event.fields["battery_percent"]
                last_battery = event.fields["battery_percent"]
        elif event.kind == "gimbal_command":
            gimbal += 1
            # Timestamp explicitly attached by the control loop, if available.
            sample_time = event.fields.get("head_timestamp")
            if sample_time is not None:
                age = event.uptime - sample_time
                if 0 <= age <= 10:
                    ages.append(age * 1000)
        elif event.kind == "gimbal_ack":
            issued = event.fields.get("command_uptime")
            if issued is not None:
                elapsed = event.uptime - issued
                if 0 <= elapsed <= 30:
                    callbacks.append(elapsed * 1000)
    return SessionMetrics(head, telemetry, gimbal, first_battery, last_battery,
                          percentile(ages, 50), percentile(ages, 95),
                          percentile(callbacks, 50), percentile(callbacks, 95),
                          dict(sorted(source_counts.items())))
