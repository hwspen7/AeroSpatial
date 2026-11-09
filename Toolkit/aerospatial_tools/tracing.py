"""Bounded causal-span diagnostics for optional/offline algorithms.

IDs, timestamps, and parent links are explicit. No implicit clock conversion is made.
"""
from __future__ import annotations

from dataclasses import dataclass
from statistics import median
import re

_NAME = re.compile(r'^[a-z][a-z0-9_-]{1,63}$')
_UINT = (1 << 64) - 1


@dataclass(frozen=True)
class TraceSpan:
    trace_id: int
    span_id: int
    parent_id: int | None
    clock_domain: int
    start_ns: int
    end_ns: int
    name: str
    outcome: str = 'ok'

    def __post_init__(self) -> None:
        for label in ('trace_id', 'span_id', 'clock_domain', 'start_ns', 'end_ns'):
            value = getattr(self, label)
            if type(value) is not int or not 0 <= value <= _UINT:
                raise ValueError('invalid ' + label)
        if not self.trace_id or not self.span_id or not self.clock_domain:
            raise ValueError('identifiers and clock domain must be positive')
        if self.parent_id is not None and (type(self.parent_id) is not int or
                                           not 1 <= self.parent_id <= _UINT or
                                           self.parent_id == self.span_id):
            raise ValueError('invalid span parent')
        if self.end_ns < self.start_ns or not _NAME.fullmatch(self.name):
            raise ValueError('invalid span duration or name')
        if self.outcome not in ('ok', 'error', 'dropped', 'skipped'):
            raise ValueError('invalid span outcome')

    @property
    def duration_ns(self) -> int:
        return self.end_ns - self.start_ns


class TraceStore:
    """Enforces parent-before-child within a bounded collection, per trace/clock domain."""

    def __init__(self, capacity: int = 100_000) -> None:
        if type(capacity) is not int or not 1 <= capacity <= 1_000_000:
            raise ValueError('invalid trace capacity')
        self.capacity = capacity
        self._spans: dict[tuple[int, int], TraceSpan] = {}

    def add(self, span: TraceSpan) -> None:
        key = (span.trace_id, span.span_id)
        if key in self._spans or len(self._spans) >= self.capacity:
            raise ValueError('duplicate span or trace budget exhausted')
        if span.parent_id is not None:
            parent = self._spans.get((span.trace_id, span.parent_id))
            if parent is None or parent.clock_domain != span.clock_domain or (
                span.start_ns < parent.start_ns
            ):
                raise ValueError('missing or incompatible causal parent')
        self._spans[key] = span

    def lineage(self, trace_id: int, span_id: int) -> tuple[str, ...]:
        names: list[str] = []
        visited: set[int] = set()
        current = self._spans.get((trace_id, span_id))
        if current is None:
            raise KeyError('unknown span')
        while current is not None:
            if current.span_id in visited:
                raise ValueError('span cycle detected')
            visited.add(current.span_id)
            names.append(current.name)
            current = (self._spans.get((trace_id, current.parent_id))
                       if current.parent_id is not None else None)
        return tuple(reversed(names))

    def report(self) -> dict[str, dict[str, float | int]]:
        groups: dict[str, list[TraceSpan]] = {}
        for span in self._spans.values():
            groups.setdefault(span.name, []).append(span)
        result: dict[str, dict[str, float | int]] = {}
        for name, group in sorted(groups.items()):
            durations = sorted(span.duration_ns for span in group)
            p95_index = max(0, (95 * len(durations) + 99) // 100 - 1)
            result[name] = {
                'count': len(group),
                'errors': sum(span.outcome == 'error' for span in group),
                'dropped': sum(span.outcome == 'dropped' for span in group),
                'median_ns': float(median(durations)),
                'p95_ns': durations[p95_index],
                'maximum_ns': durations[-1],
            }
        return result
