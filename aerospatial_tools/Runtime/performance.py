"""Reproducible offline microbenchmarks; not a real-time latency guarantee."""

from __future__ import annotations

import json
import math
import statistics
from time import perf_counter_ns
from .streaming import EventAwareSampler


def benchmark_stream(count: int = 100_000, iterations: int = 5) -> dict:
    if not 100 <= count <= 5_000_000 or not 1 <= iterations <= 20:
        raise ValueError("invalid benchmark size")
    durations_ns: list[int] = []
    last_sampler: EventAwareSampler | None = None
    for _ in range(iterations):
        sampler = EventAwareSampler()
        started = perf_counter_ns()
        for i in range(count):
            sampler.consume(i * 0.01, math.sin(i * 0.001) * 20,
                            critical=(i % 10000 == 0))
        elapsed = perf_counter_ns() - started
        durations_ns.append(elapsed)
        last_sampler = sampler
    durations_ns.sort()
    elapsed = statistics.median(durations_ns) / 1e9
    return {
        "operation": "event_aware_sampling",
        "observations": count,
        "repetitions": iterations,
        "median_seconds": round(elapsed, 6),
        "observations_per_second": round(count / elapsed),
        "retention_fraction": round(last_sampler.counters.accepted / count, 6),
        "note": "local microbenchmark; no device or flight latency guarantee",
    }


def main() -> None:
    print(json.dumps(benchmark_stream(), indent=2))


if __name__ == "__main__":
    main()
