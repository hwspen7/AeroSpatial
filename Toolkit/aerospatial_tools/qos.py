"""Deterministic offline mirror of the native optional-work token governor."""
from __future__ import annotations

from dataclasses import dataclass
import math


@dataclass(frozen=True)
class ComputePolicy:
    refill_units_per_second: float
    burst_units: float
    maximum_pressure_permille: int

    def __post_init__(self) -> None:
        if (not math.isfinite(self.refill_units_per_second) or
                not math.isfinite(self.burst_units) or
                not 0 < self.refill_units_per_second <= 1e12 or
                not 0 < self.burst_units <= 1e12 or
                type(self.maximum_pressure_permille) is not int or
                not 0 <= self.maximum_pressure_permille <= 1000):
            raise ValueError('invalid compute policy')


class ComputeBudget:
    """Limits optional compute. Never call for flight or safety paths."""

    def __init__(self, policy: ComputePolicy):
        self.policy = policy
        self.tokens = policy.burst_units
        self.last_time_ns: int | None = None
        self.counts = {'admitted': 0, 'rate_limited': 0, 'backlogged': 0,
                       'invalid': 0, 'time_regression': 0}

    def admit(self, timestamp_ns: int, units: float, pressure_permille: int) -> str:
        if (type(timestamp_ns) is not int or not 0 <= timestamp_ns <= 2**64 - 1 or
                type(units) not in (int, float) or not math.isfinite(units) or
                not 0 < units <= self.policy.burst_units or
                type(pressure_permille) is not int or not 0 <= pressure_permille <= 1000):
            self.counts['invalid'] += 1
            return 'invalid'
        if self.last_time_ns is not None and timestamp_ns < self.last_time_ns:
            self.counts['time_regression'] += 1
            return 'time_regression'
        if self.last_time_ns is not None:
            elapsed = (timestamp_ns - self.last_time_ns) / 1e9
            self.tokens = min(self.policy.burst_units,
                              self.tokens + self.policy.refill_units_per_second * min(
                                  elapsed, self.policy.burst_units / self.policy.refill_units_per_second))
        self.last_time_ns = timestamp_ns
        if pressure_permille > self.policy.maximum_pressure_permille:
            outcome = 'backlogged'
        elif self.tokens + 1e-9 < units:
            outcome = 'rate_limited'
        else:
            self.tokens = max(0.0, self.tokens - units)
            outcome = 'admitted'
        self.counts[outcome] += 1
        return outcome
