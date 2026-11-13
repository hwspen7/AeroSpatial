"""Portable offline audit contract for future user-defined quality checks."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Protocol
from .events import Event


@dataclass(frozen=True)
class Finding:
    code: str
    severity: str
    sequence: int | None
    detail: str


class AuditRule(Protocol):
    """Stateless plugin protocol; registration is explicit and never auto-imported."""

    name: str

    def inspect(self, events: list[Event]) -> list[Finding]: ...


@dataclass(frozen=True)
class AuditResult:
    records: int
    findings: list[Finding]
    evaluated_rules: list[str]

    @property
    def errors(self) -> int:
        return sum(item.severity == "error" for item in self.findings)

    def as_dict(self) -> dict:
        return {**asdict(self), "errors": self.errors}
