"""Seeded receive-side fault simulation for offline observation workloads.

Source timestamps remain unchanged. The simulator never issues flight commands.
"""
from __future__ import annotations
from dataclasses import dataclass
import random


@dataclass(frozen=True)
class FaultProfile:
    seed: int = 7
    dropout_probability: float = 0.02
    duplicate_probability: float = 0.01
    jitter_ns: int = 10_000_000
    def __post_init__(self):
        from math import isfinite
        if (type(self.seed) is not int or self.seed < 0 or self.seed >= 2**32 or
            type(self.jitter_ns) is not int or not 0 <= self.jitter_ns <= 10**9 or
            any(not isfinite(p) or not 0 <= p <= 1 for p in
                (self.dropout_probability, self.duplicate_probability))):
            raise ValueError('invalid replay fault policy')


def replay_faults(events: list[dict], profile: FaultProfile) -> dict:
    if type(events) is not list or len(events) > 1_000_000:
        raise ValueError('invalid event sequence')
    rng = random.Random(profile.seed)
    emitted = []
    dropped = duplicated = 0
    last_by_stream: dict[int, int] = {}
    for event in events:
        if (type(event) is not dict or type(event.get('stream')) is not int or
            event['stream'] not in range(1, 6) or type(event.get('timestampNs')) is not int or
            not 0 <= event['timestampNs'] <= (1 << 64) - 1):
            raise ValueError('invalid event metadata')
        stream, timestamp = event['stream'], event['timestampNs']
        if stream in last_by_stream and timestamp < last_by_stream[stream]:
            raise ValueError('source event timestamp regression')
        last_by_stream[stream] = timestamp
        if rng.random() < profile.dropout_probability:
            dropped += 1
            continue
        copy_count = 2 if rng.random() < profile.duplicate_probability else 1
        duplicated += copy_count - 1
        for _ in range(copy_count):
            jitter = rng.randint(0, profile.jitter_ns)
            emitted.append({'stream': stream, 'timestampNs': timestamp,
                            'receiveNs': timestamp + jitter, 'simulated': True})
    emitted.sort(key=lambda e: (e['receiveNs'], e['stream'], e['timestampNs']))
    return {'events': emitted, 'dropped': dropped, 'duplicated': duplicated,
            'seed': profile.seed, 'sourceEvents': len(events)}
