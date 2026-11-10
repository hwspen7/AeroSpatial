"""End-to-end real decoded video -> RANSAC match -> SQLite evidence tests."""
from __future__ import annotations
import tempfile
import unittest
from pathlib import Path

try:
    import cv2
    import numpy as np
except ImportError:
    cv2 = None

from aerospatial_tools.evidence_pipeline import EvidencePipelineConfig, index_video_evidence
from aerospatial_tools.spatial_evidence import SpatialEvidenceStore
from aerospatial_tools.cli import main


@unittest.skipUnless(cv2 is not None, 'optional OpenCV and NumPy required')
class VideoEvidenceIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        rng = np.random.default_rng(4451)
        self.texture = rng.integers(0, 256, (160, 192, 3), dtype=np.uint8)
        self.blank = np.zeros_like(self.texture)

    def video(self, name, image):
        path = self.root / name
        fourcc = cv2.VideoWriter_fourcc(*'MJPG')
        writer = cv2.VideoWriter(str(path), fourcc, 20.0, (192, 160))
        if not writer.isOpened():
            self.skipTest('MJPEG VideoWriter unavailable')
        for i in range(14):
            translation = np.float32([[1, 0, (i % 3) - 1], [0, 1, (i % 4) - 2]])
            writer.write(cv2.warpAffine(image, translation, (192, 160)))
        writer.release()
        self.assertGreater(path.stat().st_size, 100)
        return path

    def test_video_matches_store_source_provenance_without_inventing_location(self):
        reference = self.video('reference.avi', self.texture)
        query = self.video('observations.avi', self.texture)
        db = self.root / 'places.sqlite3'
        result = index_video_evidence(reference, query, db, session='flight001',
                     place_label='siteA', calibration_id='unverified',
                     config=EvidencePipelineConfig(stride=2, reference_limit=4))
        self.assertEqual(result['reference_keyframes'], 4)
        self.assertGreater(result['matched_keyframes'], 0)
        self.assertEqual(len(result['reference_sha256']), 64)
        self.assertEqual(result['location_model'], 'image_only_unlocated')
        with SpatialEvidenceStore(db) as store:
            items = store.query(session='flight001')
        self.assertEqual(len(items), result['matched_keyframes'])
        self.assertTrue(all(item.local_xyz_m is None and item.metric_frame is None for item in items))
        self.assertTrue(all(item.calibration_id == 'unverified' for item in items))
        self.assertTrue(all(item.uncertainty_ns > 0 for item in items))
        self.assertTrue(all(0.45 <= item.confidence <= 1 for item in items))
        # A repeated ingestion is not silently appended twice.
        with self.assertRaises(Exception):
            index_video_evidence(reference, query, db, session='flight001',
                                 place_label='siteA', calibration_id='unverified')

    def test_blank_reference_is_rejected(self):
        reference = self.video('blank.avi', self.blank)
        query = self.video('query.avi', self.texture)
        with self.assertRaisesRegex(ValueError, 'no usable visual reference'):
            index_video_evidence(reference, query, self.root / 'empty.sqlite3',
                                 session='flight001', place_label='siteA', calibration_id='none')

    def test_invalid_input_limits_and_destination_are_rejected(self):
        reference = self.video('r.avi', self.texture)
        with self.assertRaises(ValueError):
            EvidencePipelineConfig(stride=0)
        with self.assertRaises(ValueError):
            index_video_evidence(reference, reference, reference,
                                 session='flight001', place_label='siteA', calibration_id='none')
        with self.assertRaises(ValueError):
            index_video_evidence(reference, reference, self.root / 'db.sqlite3',
                                 session='../bad', place_label='siteA', calibration_id='none')

    def test_cli_has_video_evidence_entry(self):
        import contextlib, io
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            status = main(['video-evidence', str(self.root / 'missing.avi'),
                           str(self.root / 'missing2.avi'), str(self.root / 'out.sqlite3'),
                           '--session', 'flight001', '--place', 'siteA'])
        self.assertEqual(status, 2)
        self.assertIn('error', buffer.getvalue())


if __name__ == '__main__':
    unittest.main()
