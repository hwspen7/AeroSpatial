"""Deterministic, explicitly registered audit rules; no hardware access."""

from __future__ import annotations

from pathlib import Path
from .audit_models import AuditResult, AuditRule
from .audit_rules import CommandPairingRule, GimbalEnvelopeRule, SensorAgeRule
from .events import read_events

DEFAULT_RULES: tuple[AuditRule, ...] = (SensorAgeRule(), GimbalEnvelopeRule(), CommandPairingRule())


def audit(path: Path, rules: tuple[AuditRule, ...] = DEFAULT_RULES) -> AuditResult:
    events = list(read_events(path))
    findings = []
    names = set()
    for rule in rules:
        if rule.name in names:
            raise ValueError(f"duplicate audit rule: {rule.name}")
        names.add(rule.name)
        findings.extend(rule.inspect(events))
    return AuditResult(len(events), findings, [rule.name for rule in rules])
