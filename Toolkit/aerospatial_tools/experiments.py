"""Deterministic offline experiment records with dataset identity and error bars.

The evaluator must use the provided local RNG and must not consume external
state. Reproducibility of GPU backends is a separate, measured property.
"""
from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
import math
from pathlib import Path
import random
import statistics


@dataclass(frozen=True)
class ExperimentSpec:
    dataset: Path
    expected_sha256: str
    seed: int
    algorithm: str
    revision: str

    def __post_init__(self) -> None:
        if (type(self.expected_sha256) is not str or len(self.expected_sha256) != 64 or any(c not in '0123456789abcdef' for c in self.expected_sha256)
            or type(self.seed) is not int or not 0 <= self.seed <= 2**32 - 1
            or not self.algorithm or len(self.algorithm) > 64 or not self.revision or len(self.revision) > 64):
            raise ValueError('invalid experiment identity')


def file_digest(path: Path) -> str:
    digest = sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def percentile(samples: list[float], fraction: float) -> float:
    ordered = sorted(samples)
    index = (len(ordered) - 1) * fraction
    lo = int(index)
    hi = min(lo + 1, len(ordered) - 1)
    return ordered[lo] * (1 - (index - lo)) + ordered[hi] * (index - lo)


def evaluate_experiment(spec: ExperimentSpec, evaluator, *, bootstrap: int = 500) -> dict:
    if not 100 <= bootstrap <= 5000:
        raise ValueError('invalid bootstrap repetitions')
    if file_digest(spec.dataset) != spec.expected_sha256:
        raise ValueError('dataset checksum differs from pinned experiment')
    samples = evaluator(spec.dataset, random.Random(spec.seed))
    if type(samples) is not list or not 2 <= len(samples) <= 1_000_000 or any(
        type(v) not in (float, int) or not math.isfinite(v) or v < 0 for v in samples
    ):
        raise ValueError('evaluator must return finite nonnegative error samples')
    if len(samples) * bootstrap > 5_000_000:
        raise ValueError('bootstrap work budget exceeded')
    mean = statistics.fmean(samples)
    rms = math.sqrt(statistics.fmean(v*v for v in samples))
    rng = random.Random(spec.seed ^ 0xA51A)
    means = sorted(statistics.fmean(samples[rng.randrange(len(samples))] for _ in samples)
                   for _ in range(bootstrap))
    return {'algorithm': spec.algorithm, 'revision': spec.revision,
            'datasetSha256': spec.expected_sha256, 'seed': spec.seed,
            'sampleCount': len(samples), 'meanError': mean, 'rmsError': rms,
            'p95Error': percentile(samples, .95),
            'meanCI95': [percentile(means, .025), percentile(means, .975)]}


def save_report(path: Path, report: dict) -> None:
    content = json.dumps(report, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')
    # Exclusive create, never overwrite another experiment's evidence.
    with path.open('xb') as stream:
        stream.write(content + b'\n')
        stream.flush()
        import os
        os.fsync(stream.fileno())


def compare_reports(baseline: dict, candidate: dict, *, maximum_relative_regression: float = .05) -> dict:
    if not 0 <= maximum_relative_regression <= 1:
        raise ValueError('invalid regression allowance')
    if (baseline['datasetSha256'] != candidate['datasetSha256'] or
        baseline['sampleCount'] != candidate['sampleCount']):
        raise ValueError('incomparable experiments')
    checks = {}
    for key in ('meanError', 'rmsError', 'p95Error'):
        a, b = float(baseline[key]), float(candidate[key])
        if not math.isfinite(a) or not math.isfinite(b) or a < 0 or b < 0:
            raise ValueError('invalid experiment metric')
        checks[key] = b <= a * (1 + maximum_relative_regression) if a else b == 0
    return {'passed': all(checks.values()), 'checks': checks}
