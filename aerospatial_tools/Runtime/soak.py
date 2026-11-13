"""Repeatable performance gates for native bus throughput and memory limits.

Reports a failure only when a caller explicitly sets a threshold; host
performance numbers are not transferable to mobile devices.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path


class BenchmarkError(ValueError):
    pass


def parse_benchmark(line: str) -> dict[str, float]:
    result: dict[str, float] = {}
    for key, value in re.findall(r'([A-Za-z_]+)=([0-9.]+)', line):
        result[key] = float(value)
    for name in ('published', 'events_per_second', 'peak_live_bytes', 'payload_bytes'):
        if name not in result:
            raise BenchmarkError(f'missing benchmark field: {name}')
    return result


def measure(binary: Path, *, count: int = 100000, payload: int = 1024,
            readers: int = 4, repeats: int = 3, min_events_per_second: float = 0,
            max_peak_bytes: int = 256 * 1024 * 1024) -> dict:
    if not (1 <= count <= 20_000_000 and 1 <= payload <= 65536 and
            0 <= readers <= 16 and 1 <= repeats <= 10 and min_events_per_second >= 0):
        raise BenchmarkError('invalid benchmark configuration')
    samples = []
    for _ in range(repeats):
        proc = subprocess.run([str(binary.resolve()), str(count), str(payload),
                               str(readers), 'fast'], capture_output=True, text=True,
                              timeout=120, check=True)
        sample = parse_benchmark(proc.stdout)
        if sample['published'] != count or sample['peak_live_bytes'] > max_peak_bytes:
            raise BenchmarkError('publication count or native memory limit breached')
        samples.append(sample)
    rates = sorted(s['events_per_second'] for s in samples)
    median = rates[len(rates) // 2]
    if median < min_events_per_second:
        raise BenchmarkError('performance regression against caller-defined threshold')
    return {'median_events_per_second': median, 'min_events_per_second': rates[0],
            'max_events_per_second': rates[-1], 'peak_live_bytes': max(s['peak_live_bytes'] for s in samples),
            'payload_bytes': payload, 'readers': readers, 'repeats': repeats}


def main() -> None:
    parser = argparse.ArgumentParser(description='Run a bounded native bus performance gate')
    parser.add_argument('binary', type=Path)
    parser.add_argument('--count', type=int, default=100000)
    parser.add_argument('--payload', type=int, default=1024)
    parser.add_argument('--readers', type=int, default=4)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--minimum-rate', type=float, default=0)
    args = parser.parse_args()
    print(json.dumps(measure(args.binary, count=args.count, payload=args.payload,
                             readers=args.readers, repeats=args.repeats,
                             min_events_per_second=args.minimum_rate), indent=2))


if __name__ == '__main__':
    main()
