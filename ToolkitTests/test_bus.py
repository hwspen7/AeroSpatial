"""Multimodal event envelope and streaming audit regression tests."""
import base64
import json
from pathlib import Path
import tempfile
import unittest

from aerospatial_tools.bus_events import BusEnvelope, InvalidBusEvent, read_bus_envelopes
from aerospatial_tools.bus_audit import BusAudit


def event(**updates):
    payload = {"stream": 1, "timestampNs": 10, "sequence": 1, "clockDomain": 1,
               "kind": 0, "traceId": 0, "quality": 1, "missed": 0, "payloadBytes": 3,
               "payloadBase64": base64.b64encode(b"abc").decode()}
    payload.update(updates)
    return payload


class BusEventTests(unittest.TestCase):
    def test_parse_and_quality(self):
        record = BusEnvelope.parse(event(quality=1 | 4))
        self.assertEqual(record.payload_bytes, 3)
        audit = BusAudit()
        audit.inspect(record)
        self.assertEqual(audit.report()["head"]["estimatedClock"], 1)

    def test_gap_accounting(self):
        audit = BusAudit()
        audit.inspect(BusEnvelope.parse(event()))
        audit.inspect(BusEnvelope.parse(event(timestampNs=20, sequence=4, missed=2)))
        self.assertEqual(audit.report()["head"]["missed"], 2)
        self.assertEqual(audit.report()["head"]["gapsDetected"], 1)

    def test_gap_mismatch_rejected(self):
        audit = BusAudit()
        audit.inspect(BusEnvelope.parse(event()))
        with self.assertRaisesRegex(InvalidBusEvent, "missed count"):
            audit.inspect(BusEnvelope.parse(event(timestampNs=20, sequence=4, missed=0)))

    def test_invalid_headers(self):
        for broken in (event(stream=0), event(sequence=True), event(quality=0),
                       event(clockDomain=-1), event(timestampNs=-1), event(payloadBytes=9)):
            with self.subTest(broken=broken), self.assertRaises(InvalidBusEvent):
                BusEnvelope.parse(broken)

    def test_video_payload_rejected(self):
        with self.assertRaises(InvalidBusEvent):
            BusEnvelope.parse(event(stream=3))
        self.assertEqual(BusEnvelope.parse(event(stream=3, payloadBase64=None)).payload_bytes, 3)

    def test_multiple_streams_and_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "multimodal.jsonl"
            events = [event(), event(stream=2, timestampNs=15, payloadBase64=None),
                      event(timestampNs=12, sequence=2, missed=0)]
            path.write_text("\n".join(map(json.dumps, events)), encoding="utf-8")
            audit = BusAudit()
            for value in read_bus_envelopes(path):
                audit.inspect(value)
            self.assertEqual(audit.report()["head"]["events"], 2)
            self.assertEqual(audit.report()["telemetry"]["events"], 1)

    def test_bad_clock_domain_and_order(self):
        audit = BusAudit()
        audit.inspect(BusEnvelope.parse(event()))
        with self.assertRaisesRegex(InvalidBusEvent, "clock domain"):
            audit.inspect(BusEnvelope.parse(event(clockDomain=2, timestampNs=12, sequence=2)))
        with self.assertRaisesRegex(InvalidBusEvent, "timestamp regression"):
            audit.inspect(BusEnvelope.parse(event(timestampNs=9, sequence=2)))

    def test_oversized_line(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "invalid.jsonl"
            path.write_bytes(b" " * 32769 + b"\n")
            with self.assertRaisesRegex(InvalidBusEvent, "too long"):
                list(read_bus_envelopes(path))


if __name__ == "__main__":
    unittest.main()
