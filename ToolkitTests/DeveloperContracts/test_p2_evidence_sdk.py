from pathlib import Path
import sqlite3
import tempfile
import unittest

from aerospatial_tools.spatial_evidence import SpatialEvidence, SpatialEvidenceStore
from aerospatial_tools.sdk_contract import VerifiedPose, pose_stamped


class EvidenceTests(unittest.TestCase):
    def test_insert_query_and_no_invented_geolocation(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)/'evidence.sqlite'
            e = SpatialEvidence('obs_01', 'session_01', 'library', 3, 1000, 10,
                                77, 'calibration_01', 0.97)
            with SpatialEvidenceStore(path) as store:
                store.add(e)
                self.assertEqual(store.query(session='session_01', before_ns=1001,
                                             maximum_uncertainty_ns=10), [e])
                self.assertEqual(store.query(maximum_uncertainty_ns=9), [])
                self.assertEqual(store.query(minimum_confidence=.99), [])
                with self.assertRaises(sqlite3.IntegrityError): store.add(e)
            with SpatialEvidenceStore(path) as reopened:
                self.assertEqual(reopened.query(place_label='library'), [e])
                self.assertIsNone(reopened.query()[0].local_xyz_m)

    def test_explicit_metric_frame_validation(self):
        with self.assertRaises(ValueError):
            SpatialEvidence('o', 's', 'p', 1, 100, 0, 9, 'c', .9,
                            (1.,2.,3.), None)
        with self.assertRaises(ValueError):
            SpatialEvidence('o', 's', 'p', 1, 100, 0, 9, 'c', .9,
                            None, 'map')
        e = SpatialEvidence('o', 's', 'p', 1, 100, 0, 9, 'c', .9,
                            (1.,2.,3.), 'local_enu')
        self.assertEqual(e.metric_frame, 'local_enu')

class SDKTests(unittest.TestCase):
    def test_ros_clock_and_frame(self):
        pose = VerifiedPose('map', 1_712_000_000_000_000_321,
                            (1., 2., 3.), (0.,0.,0.,1.), 42, True)
        result = pose_stamped(pose)
        self.assertEqual(result['header']['stamp']['nanosec'], 321)
        self.assertEqual(result['pose']['position']['x'], 1)
        with self.assertRaises(ValueError):
            VerifiedPose('map', 100, (1.,2.,3.), (0.,0.,0.,1.), 42, False)
        with self.assertRaises(ValueError):
            VerifiedPose('map', 100, (1.,2.,3.), (0.,0.,0.,2.), 42, True)
        with self.assertRaises(ValueError):
            VerifiedPose('/absolute', 100, (1.,2.,3.), (0.,0.,0.,1.), 42, True)

if __name__ == '__main__': unittest.main()
