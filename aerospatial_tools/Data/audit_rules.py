"""Semantic consistency checks, separate from JSON schema validation."""

from __future__ import annotations

from .audit_models import Finding
from .events import Event


class SensorAgeRule:
    name = "sensor_age"

    def inspect(self, events: list[Event]) -> list[Finding]:
        findings = []
        for event in events:
            if event.kind != "gimbal_command":
                continue
            timestamp = event.fields.get("head_timestamp")
            if timestamp is None:
                findings.append(Finding("head_provenance_missing", "warning", event.sequence,
                                        "Command does not identify its head sample"))
                continue
            age = event.uptime - timestamp
            if age < -0.05 or age > 0.4:
                findings.append(Finding("command_stale_head", "error", event.sequence,
                                        f"Sensor-to-command age is {age:.3f}s"))
        return findings


class GimbalEnvelopeRule:
    name = "gimbal_envelope"

    def inspect(self, events: list[Event]) -> list[Finding]:
        findings = []
        for event in events:
            if event.kind != "gimbal_command":
                continue
            pitch = event.fields.get("target_pitch")
            if pitch is None or pitch < -90 or pitch > 30:
                findings.append(Finding("pitch_outside_envelope", "error", event.sequence,
                                        "Pitch command is missing or outside the kernel safety envelope"))
        return findings


class CommandPairingRule:
    name = "command_pairing"

    def inspect(self, events: list[Event]) -> list[Finding]:
        findings = []
        outstanding: dict[str, Event] = {}
        for event in events:
            # Synthetic command events represent scheduled intentions, not real SDK writes.
            if event.source == "simulator":
                continue
            key = event.session_id or "legacy"
            if event.kind == "gimbal_command":
                previous = outstanding.get(key)
                if previous is not None:
                    findings.append(Finding("overlapping_commands", "error", event.sequence,
                                            "A command was issued before the previous callback"))
                outstanding[key] = event
            if event.kind in {"gimbal_ack", "gimbal_error"}:
                issued = outstanding.pop(key, None)
                if issued is None:
                    findings.append(Finding("unpaired_callback", "warning", event.sequence,
                                            "Callback without a pending command"))
                elif event.uptime - issued.uptime > 1:
                    findings.append(Finding("slow_callback", "warning", event.sequence,
                                            "SDK callback exceeded 1 second"))
            if event.kind in {"disarm", "mode", "session_end"}:
                outstanding.pop(key, None)
        for key, event in outstanding.items():
            findings.append(Finding("unresolved_command", "warning", event.sequence,
                                    f"Session {key} ended with a command pending"))
        return findings
