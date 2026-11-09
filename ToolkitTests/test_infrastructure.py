"""Fault and recovery acceptance for the offline infrastructure."""
import tempfile
import unittest
from pathlib import Path

from aerospatial_tools.journal import Journal
from aerospatial_tools.protocol import TransportPacket, ProtocolError
from aerospatial_tools.provenance import ProvenanceTracker
from aerospatial_tools.association import FrameEvidence, associate
from aerospatial_tools.perception_models import FrameObservation, ImageBox
from aerospatial_tools.soak import parse_benchmark, BenchmarkError


class JournalTests(unittest.TestCase):
    def test_rotation_recovery_and_corrupt_tail(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            journal = Journal(path, segment_bytes=1024, maximum_segments=3)
            payloads = [bytes([i]) * 400 for i in range(6)]
            for payload in payloads:
                journal.append(payload)
            self.assertEqual(len(journal), 6)
            self.assertEqual(journal.read(4).payload, payloads[4])
            segment = sorted(path.glob('segment-*.bin'))[-1]
            with segment.open('ab') as out:
                out.write(b'\x02\x00')
            fixed = Journal(path, segment_bytes=1024, maximum_segments=3)
            self.assertEqual(len(fixed), 6)
            self.assertEqual(fixed.read(5).payload, payloads[5])
            self.assertEqual(segment.stat().st_size, 816)
            with self.assertRaises(OverflowError):
                fixed.append(b'z' * 400)

    def test_crc_and_invalid(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            journal = Journal(root, segment_bytes=1024)
            journal.append(b'test')
            with (root / 'segment-00000000.bin').open('r+b') as out:
                out.seek(8)
                out.write(b'B')
            self.assertEqual(len(Journal(root, segment_bytes=1024)), 0)
            with self.assertRaises(ValueError):
                journal.append(b'')


class ProtocolTests(unittest.TestCase):
    def test_migration_and_rejection(self):
        raw = {'stream': 1, 'timestampNs': 12, 'sequence': 1,
               'clockDomain': 1, 'kind': 0, 'traceId': 2, 'quality': 1,
               'payloadBytes': 16, 'missed': 0}
        packet = TransportPacket.from_dict(raw)
        self.assertEqual(TransportPacket.from_dict(packet.as_dict(version=2)), packet)
        self.assertEqual(TransportPacket.from_dict(packet.as_dict(version=1)), packet)
        with self.assertRaises(ProtocolError):
            TransportPacket.from_dict({**raw, 'version': 3})
        with self.assertRaises(ProtocolError):
            TransportPacket.from_dict({**raw, 'alignedNs': 12})
        aligned = TransportPacket.from_dict({**raw, 'version': 2, 'alignedNs': 12, 'uncertaintyNs': 3})
        with self.assertRaises(ProtocolError):
            aligned.as_dict(version=1)


class ProvenanceTests(unittest.TestCase):
    def test_independent_loss_categories(self):
        tracker = ProvenanceTracker()
        tracker.inspect('head', 1, source_missing=2, sampled=3)
        tracker.inspect('head', 5, transport_missed=3, rejected=4)
        total = tracker.totals()['head']
        self.assertEqual((total.upstream_missing, total.subscriber_overwritten,
                          total.deliberately_sampled, total.rejected_backpressure), (2, 3, 3, 4))
        with self.assertRaises(ValueError):
            tracker.inspect('head', 6, transport_missed=1)


class AssociationTests(unittest.TestCase):
    def test_bounded_alignment_without_geolocation(self):
        box = ImageBox(.1, .2, .3, .4)
        observation = FrameObservation.create('session', 'frame', 5.02, 'detector', 'roof', .9, box)
        frame = FrameEvidence('frame', 'session', 5.0, .01, 55)
        aligned = associate([frame], [observation], maximum_skew=.05)
        self.assertEqual(len(aligned), 1)
        self.assertEqual(aligned[0].trace_id, 55)
        self.assertEqual(associate([frame], [observation], maximum_skew=.02), [])


class BenchmarkTests(unittest.TestCase):
    def test_parser_and_corrupt_output(self):
        sample = parse_benchmark('published=10 payload_bytes=8 peak_live_bytes=16 events_per_second=120000\n')
        self.assertEqual(sample['events_per_second'], 120000)
        with self.assertRaises(BenchmarkError):
            parse_benchmark('published=1')


if __name__ == '__main__':
    unittest.main()
