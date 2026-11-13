"""Portable, deterministic SLO checks on measured algorithm execution spans."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class StageLimit:
    minimum_count: int
    maximum_p95_ns: int
    maximum_error_fraction: float

    def __post_init__(self):
        if (type(self.minimum_count) is not int or self.minimum_count < 1 or
                type(self.maximum_p95_ns) is not int or self.maximum_p95_ns < 0 or
                not 0.0 <= self.maximum_error_fraction <= 1.0):
            raise ValueError('invalid stage service-level objective')


def assess_stages(report: dict[str, dict], limits: dict[str, StageLimit]) -> dict:
    """Fails closed for absent, insufficient or over-budget stages."""
    findings = []
    for name, limit in sorted(limits.items()):
        stage = report.get(name)
        if stage is None:
            findings.append({'stage': name, 'reason': 'missing'})
            continue
        count = stage.get('count', 0)
        if type(count) is not int or count < limit.minimum_count:
            findings.append({'stage': name, 'reason': 'insufficient_samples'})
            continue
        p95 = stage.get('p95_ns')
        errors = stage.get('errors')
        if type(p95) is not int or type(errors) is not int or errors < 0 or errors > count:
            findings.append({'stage': name, 'reason': 'invalid_statistics'})
            continue
        if p95 > limit.maximum_p95_ns:
            findings.append({'stage': name, 'reason': 'latency_exceeded'})
        if errors / count > limit.maximum_error_fraction:
            findings.append({'stage': name, 'reason': 'error_fraction_exceeded'})
    return {'passed': not findings, 'findings': findings}
