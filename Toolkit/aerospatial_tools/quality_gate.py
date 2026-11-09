"""Reproducible, machine-readable release gates for offline sessions."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from .analysis import analyze
from .audit import audit
from .validation import validate


@dataclass(frozen=True)
class QualityThresholds:
    minimum_head_samples: int = 0
    minimum_telemetry_samples: int = 0
    maximum_sensor_command_p95_ms: float | None = None
    maximum_semantic_errors: int = 0
    maximum_integrity_issues: int = 0

    @staticmethod
    def from_file(path: Path) -> "QualityThresholds":
        raw = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(raw, dict):
            raise ValueError("quality thresholds must be a JSON object")
        allowed = set(QualityThresholds.__dataclass_fields__)
        if set(raw) - allowed:
            raise ValueError("unknown quality threshold key")
        for name in ("minimum_head_samples", "minimum_telemetry_samples",
                     "maximum_semantic_errors", "maximum_integrity_issues"):
            value = raw.get(name, 0)
            if type(value) is not int or value < 0:
                raise ValueError(f"{name} must be a nonnegative integer")
        limit = raw.get("maximum_sensor_command_p95_ms")
        if limit is not None and (isinstance(limit, bool) or not isinstance(limit, (int, float))
                                  or not math.isfinite(limit) or limit < 0):
            raise ValueError("p95 bound must be finite and nonnegative")
        return QualityThresholds(**raw)


def evaluate(path: Path, thresholds: QualityThresholds) -> dict:
    integrity = validate(path)
    semantic = audit(path)
    metrics = analyze(path)
    failures: list[str] = []
    if integrity.issue_count > thresholds.maximum_integrity_issues:
        failures.append("integrity_issue_budget_exceeded")
    if semantic.errors > thresholds.maximum_semantic_errors:
        failures.append("semantic_error_budget_exceeded")
    if metrics.head_samples < thresholds.minimum_head_samples:
        failures.append("insufficient_head_samples")
    if metrics.telemetry_samples < thresholds.minimum_telemetry_samples:
        failures.append("insufficient_telemetry_samples")
    bound = thresholds.maximum_sensor_command_p95_ms
    if bound is not None and (metrics.sensor_to_command_age_ms_p95 is None or
                              metrics.sensor_to_command_age_ms_p95 > bound):
        failures.append("sensor_to_command_p95_exceeded_or_missing")
    return {
        "passed": not failures,
        "failures": failures,
        "integrity_issue_count": integrity.issue_count,
        "semantic_error_count": semantic.errors,
        "head_samples": metrics.head_samples,
        "telemetry_samples": metrics.telemetry_samples,
        "sensor_to_command_p95_ms": metrics.sensor_to_command_age_ms_p95,
        "note": "Sensor-to-command age is not radio transmission or motor response latency.",
    }
