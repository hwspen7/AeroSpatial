"""Constant-memory latency, throughput and resource monitoring for offline runs."""
from __future__ import annotations
from dataclasses import dataclass, field
import math

# Upper limits in microseconds. Deliberately include a capped slow tail.
_BUCKETS_US = (50, 100, 250, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 500000)


@dataclass
class RuntimeMonitor:
    received: int = 0
    dropped: int = 0
    maximum_live_bytes: int = 0
    maximum_delay_us: float = 0
    bucket_counts: list[int] = field(default_factory=lambda: [0] * (len(_BUCKETS_US) + 1))
    _first_ns: int | None = None
    _last_ns: int | None = None

    def record(self, *, receive_ns: int, latency_ns: int, live_bytes: int,
               dropped: int = 0) -> None:
        values = (receive_ns, latency_ns, live_bytes, dropped)
        if any(type(v) is not int or v < 0 for v in values):
            raise ValueError('telemetry must be nonnegative integral')
        if self._last_ns is not None and receive_ns < self._last_ns:
            raise ValueError('non-monotonic receive time')
        self._first_ns = receive_ns if self._first_ns is None else self._first_ns
        self._last_ns = receive_ns
        self.received += 1
        self.dropped += dropped
        self.maximum_live_bytes = max(self.maximum_live_bytes, live_bytes)
        delay_us = latency_ns / 1000
        self.maximum_delay_us = max(self.maximum_delay_us, delay_us)
        idx = next((i for i, limit in enumerate(_BUCKETS_US) if delay_us <= limit), len(_BUCKETS_US))
        self.bucket_counts[idx] += 1

    def percentile_upper_us(self, fraction: float) -> float:
        if not 0 < fraction <= 1 or not self.received:
            raise ValueError('invalid percentile or empty monitor')
        target = math.ceil(self.received * fraction)
        current = 0
        for index, count in enumerate(self.bucket_counts):
            current += count
            if current >= target:
                return float(_BUCKETS_US[index]) if index < len(_BUCKETS_US) else math.inf
        raise RuntimeError('histogram invariant violated')

    def report(self) -> dict[str, float | int]:
        span = (self._last_ns - self._first_ns) / 1e9 if self.received >= 2 else 0
        return {'received': self.received, 'dropped': self.dropped,
                'throughput_per_second': (self.received - 1) / span if span > 0 else 0,
                'max_live_bytes': self.maximum_live_bytes,
                'max_delay_us': self.maximum_delay_us,
                'p95_upper_us': self.percentile_upper_us(.95) if self.received else 0,
                'p99_upper_us': self.percentile_upper_us(.99) if self.received else 0}

    def enforce(self, *, max_live_bytes: int, max_p99_us: float,
                max_drop_fraction: float) -> None:
        if max_live_bytes < 0 or max_p99_us < 0 or not 0 <= max_drop_fraction <= 1:
            raise ValueError('invalid monitoring gate')
        samples = self.received + self.dropped
        drop_fraction = self.dropped / samples if samples else 0
        if (self.maximum_live_bytes > max_live_bytes or
                self.received and self.percentile_upper_us(.99) > max_p99_us or
                drop_fraction > max_drop_fraction):
            raise RuntimeError('runtime quality gate violated')
