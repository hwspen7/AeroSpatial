"""Bounded-memory telemetry stream sampling and quality summaries.

The sampler retains first, last, and significant changes without influencing flight control.
Its decisions apply only to stored/visualized observations.
"""

from __future__ import annotations

from dataclasses import dataclass
import math


@dataclass(frozen=True)
class StreamPolicy:
    minimum_interval: float = 0.025
    maximum_interval: float = 0.5
    significant_change: float = 3.0

    def __post_init__(self) -> None:
        if not (0 < self.minimum_interval <= self.maximum_interval <= 60):
            raise ValueError("invalid stream intervals")
        if not math.isfinite(self.significant_change) or self.significant_change < 0:
            raise ValueError("invalid significance threshold")


@dataclass
class StreamCounters:
    seen: int = 0
    accepted: int = 0
    downsampled: int = 0
    invalid: int = 0
    backwards: int = 0


class EventAwareSampler:
    """Keep sparse steady-state data while retaining significant transitions.

    This object does not own a queue or allocate per observation.
    """

    def __init__(self, policy: StreamPolicy | None = None) -> None:
        self.policy = policy or StreamPolicy()
        self.counters = StreamCounters()
        self._time: float | None = None
        self._value: float | None = None
        self._seen_time: float | None = None

    def consume(self, timestamp: float, value: float, *, critical: bool = False) -> bool:
        self.counters.seen += 1
        if not (math.isfinite(timestamp) and math.isfinite(value) and timestamp >= 0):
            self.counters.invalid += 1
            return False
        if self._seen_time is not None and timestamp < self._seen_time:
            self.counters.backwards += 1
            return False
        self._seen_time = timestamp
        elapsed = timestamp - self._time if self._time is not None else math.inf
        change = abs(value - self._value) if self._value is not None else math.inf
        accept = (critical or elapsed >= self.policy.maximum_interval or
                  (elapsed >= self.policy.minimum_interval and
                   change >= self.policy.significant_change) or self._time is None)
        if accept:
            self._time, self._value = timestamp, value
            self.counters.accepted += 1
        else:
            self.counters.downsampled += 1
        return accept

    def reset(self) -> None:
        self.counters = StreamCounters()
        self._time = None
        self._value = None
        self._seen_time = None


@dataclass
class OnlineMoments:
    """Numerically stable constant-memory distribution summary."""

    count: int = 0
    mean: float = 0.0
    m2: float = 0.0
    minimum: float = math.inf
    maximum: float = -math.inf

    def add(self, value: float) -> None:
        if not math.isfinite(value):
            raise ValueError("nonfinite observation")
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count
        self.m2 += delta * (value - self.mean)
        self.minimum = min(self.minimum, value)
        self.maximum = max(self.maximum, value)

    @property
    def variance(self) -> float:
        return self.m2 / self.count if self.count else math.nan

    def report(self) -> dict[str, float | int | None]:
        return {
            "count": self.count,
            "mean": self.mean if self.count else None,
            "standard_deviation": math.sqrt(self.variance) if self.count else None,
            "minimum": self.minimum if self.count else None,
            "maximum": self.maximum if self.count else None,
        }
