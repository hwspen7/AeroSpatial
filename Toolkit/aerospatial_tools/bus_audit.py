"""Constant-memory per-stream integrity audit for transport metadata envelopes."""
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
    stale: int = 0
    simulated: int = 0
    upstream_gap: int = 0
    upstream_missing: int = 0
    sampled: int = 0
    rejected_at_source: int = 0
    gaps_detected: int = 0
    initial_gap_observed: int = 0
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
        else:
            # A subscriber may intentionally start at the latest sequence. Without
            # its creation cursor, earlier records are not known to be missing.
            if event.missed > event.sequence - 1:
                raise InvalidBusEvent("initial missed exceeds preceding sequence range")
            self.initial_gap_observed = int(event.missed > 0)
            self.gaps_detected += self.initial_gap_observed
        self.previous_sequence = event.sequence
        self.previous_timestamp = event.timestamp_ns
        self.clock_domain = event.clock_domain
        self.events += 1
        self.missed += event.missed
        self.bytes += event.payload_bytes
        self.low_confidence += bool(event.quality & (1 << 3))
        self.estimated_clock += bool(event.quality & (1 << 2))
        self.stale += bool(event.quality & (1 << 4))
        self.simulated += bool(event.quality & (1 << 1))
        self.upstream_gap += bool(event.quality & (1 << 5))
        self.upstream_missing += event.upstream_missing
        self.sampled += event.sampled
        self.rejected_at_source += event.rejected


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
                "stale": value.stale,
                "simulated": value.simulated,
                "upstreamGap": value.upstream_gap,
                "upstreamMissing": value.upstream_missing,
                "deliberatelySampled": value.sampled,
                "rejectedAtSource": value.rejected_at_source,
                "gapsDetected": value.gaps_detected,
                "initialGapObserved": value.initial_gap_observed,
            }
            for stream, value in sorted(self.streams.items())
        }
