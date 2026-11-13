"""A P3 acceptance gate must not pass missing or fabricated metric evidence."""
import tempfile
import unittest
from pathlib import Path
from aerospatial_tools.evidence_gate import evaluate_evidence
from aerospatial_tools.spatial_evidence import SpatialEvidence, SpatialEvidenceStore


class EvidenceGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.db = Path(self.tmp.name) / 'evidence.sqlite3'

    def item(self, index, **changes):
        data = dict(identifier=f'item{index}', session='recording', place_label='siteA',
                    frame_index=index, capture_ns=100000*index, uncertainty_ns=1000,
                    trace_id=index+1, calibration_id='unverified', confidence=0.75)
        data.update(changes)
        return SpatialEvidence(**data)

    def test_missing_evidence_fails_closed(self):
        result = evaluate_evidence(self.db, session='recording')
        self.assertFalse(result['passed'])
        self.assertIn('not_enough_verified_matches', result['issues'])

    def test_requires_multiple_verified_image_level_observations(self):
        with SpatialEvidenceStore(self.db) as store:
            for i in range(4):
                store.add(self.item(i))
        self.assertTrue(evaluate_evidence(self.db, session='recording')['passed'])
        self.assertFalse(evaluate_evidence(self.db, session='other')['passed'])

    def test_bad_clock_or_inlier_ratio_fails(self):
        with SpatialEvidenceStore(self.db) as store:
            store.add(self.item(1))
            store.add(self.item(2, uncertainty_ns=1_000_000))
            store.add(self.item(3, confidence=0.3))
        result = evaluate_evidence(self.db, session='recording', maximum_uncertainty_ns=10_000)
        self.assertIn('clock_uncertainty_exceeded', result['issues'])
        self.assertIn('visual_inlier_ratio_below_gate', result['issues'])

    def test_claimed_metric_position_not_accepted_by_image_only_gate(self):
        with SpatialEvidenceStore(self.db) as store:
            for i in range(3):
                store.add(self.item(i, local_xyz_m=(1, 2, 3), metric_frame='map'))
        self.assertIn('unverified_metric_position',
                      evaluate_evidence(self.db, session='recording')['issues'])


if __name__ == '__main__':
    unittest.main()
