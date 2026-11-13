"""Distinguish transport loss, source gaps, and deliberate downsampling."""
from __future__ import annotations
from dataclasses import dataclass


@dataclass(frozen=True)
class ProvenanceDelta:
    upstream_missing: int = 0
    subscriber_overwritten: int = 0
    deliberately_sampled: int = 0
    rejected_backpressure: int = 0

    def __post_init__(self):
        if any(type(value) is not int or value < 0 for value in self.__dict__.values()):
            raise ValueError('provenance counters must be unsigned integers')


class ProvenanceTracker:
    def __init__(self):
        self._last_sequence: dict[str, int] = {}
        self._totals: dict[str, ProvenanceDelta] = {}

    def inspect(self, stream: str, sequence: int, *, transport_missed: int = 0,
                source_missing: int = 0, sampled: int = 0, rejected: int = 0) -> ProvenanceDelta:
        if not stream or type(sequence) is not int or sequence <= 0:
            raise ValueError('invalid stream or sequence')
        current = ProvenanceDelta(source_missing, transport_missed, sampled, rejected)
        previous = self._last_sequence.get(stream)
        if previous is not None:
            if sequence <= previous or sequence - previous - 1 != transport_missed:
                raise ValueError('transport gap does not match subscriber sequence')
        elif transport_missed > sequence - 1:
            raise ValueError('initial gap exceeds possible prior messages')
        self._last_sequence[stream] = sequence
        old = self._totals.get(stream, ProvenanceDelta())
        self._totals[stream] = ProvenanceDelta(*(
            a + b for a, b in zip(old.__dict__.values(), current.__dict__.values())))
        return current

    def totals(self) -> dict[str, ProvenanceDelta]:
        return dict(self._totals)
