import unittest
from aerospatial_tools.bus_events import BusEnvelope, InvalidBusEvent
from aerospatial_tools.bus_audit import BusAudit

class BusProtocolExtendedTests(unittest.TestCase):
    def test_v2_provenance_and_alignment(self):
        raw = {'version': 2, 'stream': 1, 'timestampNs': 1, 'sequence': 1,
               'clockDomain': 1, 'kind': 0, 'traceId': 0, 'quality': 1,
               'missed': 0, 'payloadBytes': 0, 'upstreamMissing': 3,
               'sampled': 4, 'rejected': 2, 'alignedNs': 1, 'uncertaintyNs': 2}
        event = BusEnvelope.parse(raw)
        audit = BusAudit()
        audit.inspect(event)
        self.assertEqual(audit.report()['head']['upstreamMissing'], 3)
        self.assertEqual(audit.report()['head']['deliberatelySampled'], 4)
        self.assertEqual(audit.report()['head']['rejectedAtSource'], 2)
        with self.assertRaises(InvalidBusEvent):
            BusEnvelope.parse({**raw, 'version': 1})
