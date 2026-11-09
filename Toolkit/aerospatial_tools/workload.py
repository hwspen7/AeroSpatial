"""Reproducible workload replay with independent compute budgets per stream."""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
import random

from .qos import ComputeBudget, ComputePolicy


@dataclass(frozen=True)
class WorkloadProfile:
    seed: int = 7
    samples: int = 3000
    interval_ns: int = 10_000_000

    def __post_init__(self):
        if (type(self.samples) is not int or not 1 <= self.samples <= 1_000_000 or
                type(self.interval_ns) is not int or not 1 <= self.interval_ns <= 1_000_000_000 or
                type(self.seed) is not int):
            raise ValueError('invalid workload profile')


def replay(profile: WorkloadProfile) -> dict:
    """Apply load shaping to optional video/perception/diagnostic work only.

    All generated events are synthetic; no device or aircraft is contacted.
    """
    generator = random.Random(profile.seed)
    budgets = {
        'video': ComputeBudget(ComputePolicy(65, 10, 900)),
        'perception': ComputeBudget(ComputePolicy(30, 6, 750)),
        'diagnostic': ComputeBudget(ComputePolicy(10, 4, 950)),
    }
    counts = {name: Counter() for name in budgets}
    for index in range(profile.samples):
        timestamp_ns = index * profile.interval_ns
        # Alternating high and low pressure episodes reproduce overload recovery.
        pressure = 920 if (index // 200) % 3 == 1 else generator.randrange(0, 400)
        for name in budgets:
            cost = 0.5 + generator.random() * 1.5
            result = budgets[name].admit(timestamp_ns, cost, pressure)
            counts[name][result] += 1
    return {
        'seed': profile.seed,
        'samples_per_stream': profile.samples,
        'counts': {name: dict(sorted(group.items())) for name, group in counts.items()},
        'admission_fraction': {name: round(group['admitted'] / profile.samples, 6)
                               for name, group in counts.items()},
    }
