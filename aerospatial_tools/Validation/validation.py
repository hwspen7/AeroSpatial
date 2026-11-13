"""Deterministic integrity checks for monotonically sequenced session records."""

from __future__ import annotations

from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from .events import read_events


@dataclass(frozen=True)
class ValidationResult:
    total_records: int
    sessions: int
    counts_by_kind: dict[str, int]
    duration_seconds: float
    issue_count: int
    issues: list[str]

    def as_dict(self) -> dict:
        return asdict(self)


def validate(path: Path, max_issues: int = 50) -> ValidationResult:
    counters: Counter[str] = Counter()
    issues: list[str] = []
    sessions: dict[str, tuple[int, float]] = {}
    first: float | None = None
    previous: float | None = None
    last: float | None = None
    issue_count = 0

    def issue(message: str) -> None:
        nonlocal issue_count
        issue_count += 1
        if len(issues) < max_issues:
            issues.append(message)

    for number, event in enumerate(read_events(path), start=1):
        counters[event.kind] += 1
        if first is None:
            first = event.uptime
        if previous is not None and event.uptime < previous:
            issue(f"record {number}: uptime decreased")
        previous = event.uptime
        last = event.uptime
        if event.session_id is not None:
            prior = sessions.get(event.session_id)
            if prior is None:
                if event.sequence != 0:
                    issue(f"record {number}: session does not start at sequence 0")
            else:
                prev_seq, prev_time = prior
                if event.sequence != prev_seq + 1:
                    issue(f"record {number}: noncontiguous sequence")
                if event.uptime < prev_time:
                    issue(f"record {number}: session uptime decreased")
            sessions[event.session_id] = (event.sequence, event.uptime)

    total = sum(counters.values())
    if total == 0:
        issue("session contains no records")
    return ValidationResult(total, len(sessions), dict(sorted(counters.items())),
                            max(0, (last or 0) - (first or 0)), issue_count, issues)
