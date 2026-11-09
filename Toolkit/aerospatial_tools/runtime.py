"""Offline synchronous algorithm execution with guarded dependencies and failures.

Processors run in the caller's process. This is NOT a sandbox or real-time executor.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Any
import json
import time

from .algorithm import AlgorithmManifest, AlgorithmRegistry
from .qos import ComputeBudget, ComputePolicy

Processor = Callable[[dict[str, Any]], dict[str, Any]]


@dataclass
class ExecutionStats:
    calls: int = 0
    successful: int = 0
    rejected: int = 0
    failed: int = 0
    quarantined: bool = False
    consecutive_failures: int = 0
    over_deadline: int = 0
    maximum_duration_ns: int = 0


class AlgorithmRuntime:
    """Bounded optional workload executor for synthetic/offline metadata.

    A timeout is only measurable *after* a synchronous function returns. Never
    pass untrusted plugins or time-critical aircraft control callbacks here.
    """

    def __init__(self, registry: AlgorithmRegistry, *, failure_limit: int = 3):
        if type(failure_limit) is not int or not 1 <= failure_limit <= 100:
            raise ValueError('invalid failure limit')
        self.plan = registry.ordered()
        if any(item.requires_hardware for item in self.plan):
            raise ValueError('offline runtime cannot execute hardware-dependent algorithms')
        self.failure_limit = failure_limit
        self.processors: dict[str, Processor] = {}
        self.stats = {item.identifier: ExecutionStats() for item in self.plan}
        self.budgets = {
            item.identifier: ComputeBudget(ComputePolicy(1000.0 / item.deadline_milliseconds,
                                                           4.0, 900))
            for item in self.plan
        }

    def bind(self, identifier: str, processor: Processor) -> None:
        if identifier not in self.stats or not callable(processor):
            raise ValueError('unknown algorithm or invalid processor')
        if identifier in self.processors:
            raise ValueError('algorithm already bound')
        self.processors[identifier] = processor

    def execute(self, timestamp_ns: int, event: dict[str, Any], *, pressure: int = 0) -> dict:
        if type(timestamp_ns) is not int or not 0 <= timestamp_ns <= (1 << 64) - 1:
            raise ValueError('invalid event timestamp')
        if type(event) is not dict or len(event) > 128:
            raise ValueError('invalid input event')
        if any(item.identifier not in self.processors for item in self.plan):
            raise ValueError('unbound algorithm in execution plan')
        if len(json.dumps(event, allow_nan=False).encode('utf-8')) > 8 * 1024 * 1024:
            raise ValueError('input event too large')
        context = dict(event)
        outcome: dict[str, str] = {}
        for spec in self.plan:
            name = spec.identifier
            stat = self.stats[name]
            stat.calls += 1
            if stat.quarantined or any(outcome.get(parent) != 'ok'
                                       for parent in spec.dependencies):
                stat.rejected += 1
                outcome[name] = 'blocked'
                continue
            admission = self.budgets[name].admit(timestamp_ns, 1.0, pressure)
            if admission != 'admitted':
                stat.rejected += 1
                outcome[name] = admission
                continue
            start_ns = time.perf_counter_ns()
            try:
                extension = self.processors[name](dict(context))
                duration_ns = time.perf_counter_ns() - start_ns
                stat.maximum_duration_ns = max(stat.maximum_duration_ns, duration_ns)
                if duration_ns > spec.deadline_milliseconds * 1_000_000:
                    stat.over_deadline += 1
                    raise TimeoutError('algorithm exceeded declared deadline')
                if type(extension) is not dict or len(extension) > 128 or any(
                    type(key) is not str or not key.startswith(name + '.') for key in extension
                ) or any(key in context for key in extension):
                    raise ValueError('invalid or non-namespaced processor output')
                # This is a conservative output-size bound, not an OS memory quota.
                if len(json.dumps(extension, allow_nan=False).encode('utf-8')) > spec.memory_budget_bytes:
                    raise ValueError('output exceeds declared memory budget')
                context.update(extension)
                stat.successful += 1
                stat.consecutive_failures = 0
                outcome[name] = 'ok'
            except Exception:  # isolate an optional plugin failure from dependent processors
                stat.failed += 1
                stat.consecutive_failures += 1
                stat.quarantined = stat.consecutive_failures >= self.failure_limit
                outcome[name] = 'failed'
        return {'status': outcome, 'context': context}

    def clear_quarantine(self, identifier: str) -> None:
        if identifier not in self.stats:
            raise ValueError('unknown algorithm')
        self.stats[identifier].quarantined = False
        self.stats[identifier].consecutive_failures = 0
