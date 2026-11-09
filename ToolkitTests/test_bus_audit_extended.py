"""Regression tests for initial cursor uncertainty and quality provenance."""
import unittest

from aerospatial_tools.bus_events import BusEnvelope, InvalidBusEvent
from aerospatial_tools.bus_audit import BusAudit


def record(sequence, missed=0, quality=1, timestamp=100):
    return BusEnvelope.parse({
        "stream": 1, "timestampNs": timestamp, "sequence": sequence,
        "clockDomain": 2, "kind": 0, "traceId": 0,
        "quality": quality, "missed": missed, "payloadBytes": 0,
    })


class ExtendedAuditTests(unittest.TestCase):
    def test_first_message_gap_can_be_reported(self):
        audit = BusAudit()
        audit.inspect(record(45, 44, quality=1 | 2 | 4 | 8 | 16 | 32))
        result = audit.report()["head"]
        self.assertEqual(result["missed"], 44)
        self.assertEqual(result["initialGapObserved"], 1)
        self.assertEqual(result["gapsDetected"], 1)
        self.assertEqual(result["stale"], 1)
        self.assertEqual(result["upstreamGap"], 1)
        self.assertEqual(result["simulated"], 1)

    def test_first_message_from_latest_is_not_assumed_missing(self):
        audit = BusAudit()
        audit.inspect(record(100, 0))
        self.assertEqual(audit.report()["head"]["missed"], 0)
        audit.inspect(record(105, 4, timestamp=120))
        self.assertEqual(audit.report()["head"]["gapsDetected"], 1)

    def test_initial_missed_cannot_exceed_sequence(self):
        with self.assertRaisesRegex(InvalidBusEvent, "initial missed"):
            BusAudit().inspect(record(2, 2))


if __name__ == "__main__":
    unittest.main()
