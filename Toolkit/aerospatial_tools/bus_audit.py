"""Streaming multimodal bus audit with O(number of streams) state."""
from __future__ import annotations

from dataclasses import dataclass, field
from .bus_events import BusEnvelope, InvalidBusEvent, STREAM_NAMES


@dataclass
class TopicAudit:
    events: int = 0
    missed: int = 0
    bytes: int = 0
    low_confidence: int = 0
    estimated_clock: int = 0
    gaps_detected: int = 0
    previous_sequence: int = 0
    previous_timestamp: int = 0
    clock_domain: int = 0

    def inspect(self, event: BusEnvelope) -> None:
        if self.events:
            if event.sequence <= self.previous_sequence:
                raise InvalidBusEvent("non-increasing sequence")
            if event.timestamp_ns < self.previous_timestamp:
                raise InvalidBusEvent("timestamp regression")
            if event.clock_domain != self.clock_domain:
                raise InvalidBusEvent("clock domain changed inside stream")
            gap = event.sequence - self.previous_sequence - 1
            if event.missed != gap:
                raise InvalidBusEvent("missed count disagrees with sequence gap")
            self.gaps_detected += int(gap > 0)
        self.previous_sequence = event.sequence
        self.previous_timestamp = event.timestamp_ns
        self.clock_domain = event.clock_domain
        self.events += 1
        self.missed += event.missed
        self.bytes += event.payload_bytes
        self.low_confidence += bool(event.quality & (1 << 3))
        self.estimated_clock += bool(event.quality & (1 << 2))


@dataclass
class BusAudit:
    streams: dict[int, TopicAudit] = field(default_factory=dict)

    def inspect(self, event: BusEnvelope) -> None:
        self.streams.setdefault(event.stream, TopicAudit()).inspect(event)

    def report(self) -> dict[str, dict[str, int]]:
        return {
            STREAM_NAMES[stream]: {
                "events": value.events,
                "missed": value.missed,
                "bytes": value.bytes,
                "lowConfidence": value.low_confidence,
                "estimatedClock": value.estimated_clock,
                "gapsDetected": value.gaps_detected,
            }
            for stream, value in sorted(self.streams.items())
        }
