"""Declarative, read-only algorithm registry shared with Swift's manifest JSON.

This module validates algorithm dependencies, not dynamic code or trust boundaries.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re

_IDENTIFIER = re.compile(r'^[a-z][a-z0-9_-]{2,63}$')
_FIELDS = {'identifier', 'inputs', 'outputs', 'dependencies',
           'memoryBudgetBytes', 'deadlineMilliseconds', 'deterministic', 'requiresHardware'}


@dataclass(frozen=True)
class AlgorithmManifest:
    identifier: str
    inputs: tuple[int, ...]
    outputs: tuple[int, ...]
    dependencies: tuple[str, ...]
    memory_budget_bytes: int
    deadline_milliseconds: int
    deterministic: bool
    requires_hardware: bool

    @classmethod
    def parse(cls, value: dict) -> 'AlgorithmManifest':
        if type(value) is not dict or set(value) != _FIELDS:
            raise ValueError('algorithm manifest fields must match the contract')
        if any(type(value[name]) is not list for name in ('inputs', 'outputs', 'dependencies')):
            raise ValueError('stream and dependency fields must be arrays')
        if any(type(item) is not int or item not in range(1, 6)
               for name in ('inputs', 'outputs') for item in value[name]):
            raise ValueError('invalid stream identifier')
        if not value['inputs'] or not value['outputs'] or len(set(value['inputs'])) != len(value['inputs']) or len(set(value['outputs'])) != len(value['outputs']):
            raise ValueError('empty or duplicate streams')
        if not set(value['outputs']) <= {4, 5}:
            raise ValueError('an algorithm cannot publish aircraft or head source streams')
        identifier = value['identifier']
        deps = value['dependencies']
        if type(identifier) is not str or not _IDENTIFIER.fullmatch(identifier):
            raise ValueError('invalid algorithm identifier')
        if any(type(dep) is not str or not _IDENTIFIER.fullmatch(dep) for dep in deps) or len(set(deps)) != len(deps) or identifier in deps:
            raise ValueError('invalid dependencies')
        budget = value['memoryBudgetBytes']
        deadline = value['deadlineMilliseconds']
        if (type(budget) is not int or not 1 <= budget <= 536_870_912 or
                type(deadline) is not int or not 1 <= deadline <= 10_000 or
                type(value['deterministic']) is not bool or type(value['requiresHardware']) is not bool):
            raise ValueError('invalid algorithm resource or capability declaration')
        return cls(identifier, tuple(value['inputs']), tuple(value['outputs']), tuple(deps),
                   budget, deadline, value['deterministic'], value['requiresHardware'])


class AlgorithmRegistry:
    def __init__(self):
        self._algorithms: dict[str, AlgorithmManifest] = {}

    def register(self, algorithm: AlgorithmManifest) -> None:
        if len(self._algorithms) >= 256:
            raise ValueError('algorithm registry capacity exceeded')
        if algorithm.identifier in self._algorithms:
            raise ValueError('duplicate algorithm identifier')
        self._algorithms[algorithm.identifier] = algorithm

    def ordered(self) -> tuple[AlgorithmManifest, ...]:
        complete: set[str] = set()
        visiting: set[str] = set()
        order: list[AlgorithmManifest] = []

        def visit(identifier: str) -> None:
            if identifier in complete:
                return
            if identifier in visiting:
                raise ValueError('algorithm dependency cycle')
            if identifier not in self._algorithms:
                raise ValueError('missing dependency: ' + identifier)
            visiting.add(identifier)
            item = self._algorithms[identifier]
            for dep in sorted(item.dependencies):
                visit(dep)
                if not set(self._algorithms[dep].outputs).intersection(item.inputs):
                    raise ValueError('dependency output does not feed downstream input')
            visiting.remove(identifier)
            complete.add(identifier)
            order.append(item)

        for identifier in sorted(self._algorithms):
            visit(identifier)
        return tuple(order)


def load_manifests(path: Path) -> AlgorithmRegistry:
    records = json.loads(path.read_text(encoding='utf-8'))
    if type(records) is not list or len(records) > 256:
        raise ValueError('expected at most 256 algorithm manifests')
    registry = AlgorithmRegistry()
    for record in records:
        registry.register(AlgorithmManifest.parse(record))
    registry.ordered()
    return registry
