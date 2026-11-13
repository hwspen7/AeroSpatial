import unittest
import math
try:
    import numpy as np
    import cv2
    import scipy
except ImportError as missing:
    raise unittest.SkipTest("Optional spatial mapping extras unavailable") from missing

import numpy as np
from aerospatial_tools.fusion import DelayedPositionFusion
from aerospatial_tools.estimation_quality import evaluate_nees, validate_covariance
from aerospatial_tools.visual_geometry import recover_motion_from_correspondences


class FusionP1Tests(unittest.TestCase):
    def test_delayed_updates_replay_to_same_state_as_in_order(self):
        first = DelayedPositionFusion(maximum_lag_s=5)
        delayed = DelayedPositionFusion(maximum_lag_s=5)
        for fusion in (first, delayed):
            for i in range(11):
                self.assertTrue(fusion.append_acceleration(i*.1, (1.0, 0, 0)))
        self.assertTrue(first.observe_position(.3, (.05, 0, 0), .5))
        self.assertTrue(first.observe_position(.7, (.24, 0, 0), .5))
        self.assertTrue(delayed.observe_position(.7, (.24, 0, 0), .5))
        self.assertTrue(delayed.observe_position(.3, (.05, 0, 0), .5))
        self.assertTrue(np.allclose(first.snapshot.position_m, delayed.snapshot.position_m))
        self.assertTrue(np.allclose(first.snapshot.covariance, delayed.snapshot.covariance))
        self.assertFalse(delayed.observe_position(.5, (10000, 0, 0), .1))
        self.assertEqual(delayed.snapshot.gated_positions, 1)
        self.assertFalse(delayed.observe_position(-1, (0, 0, 0), .1))
        self.assertFalse(delayed.append_acceleration(.5, (0,0,0)))
        self.assertTrue(np.linalg.eigvalsh(delayed.snapshot.covariance).min() > 0)

    def test_sliding_window_remains_bounded_over_long_input(self):
        s = DelayedPositionFusion(maximum_lag_s=.5, maximum_events=100)
        for i in range(3000):
            self.assertTrue(s.append_acceleration(i*.01, (0,0,0)))
        self.assertLessEqual(len(s.events), 55)
        self.assertTrue(s.observe_position(29.8, (0,0,0), .5))
        self.assertFalse(s.observe_position(28., (0,0,0), .5))
        self.assertTrue(np.linalg.eigvalsh(s.snapshot.covariance).min()>0)

    def test_lag_and_event_capacity_enforced(self):
        s = DelayedPositionFusion(maximum_lag_s=.2, maximum_events=8)
        for i in range(8): self.assertTrue(s.append_acceleration(.01*i, (0, 0, 0)))
        self.assertFalse(s.append_acceleration(.08, (0,0,0)))
        self.assertFalse(s.observe_position(.01, (0,0,0), 1))

    def test_covariance_and_statistical_consistency(self):
        with self.assertRaises(ValueError): validate_covariance([[1, 2], [2, -1]])
        rng = np.random.default_rng(122)
        residual = rng.normal(size=(500,3))
        cov = np.tile(np.eye(3), (500,1,1))
        report = evaluate_nees(residual, cov)
        self.assertEqual(report.sample_count, 500)
        self.assertTrue(2.5 < report.mean_nees < 3.6)
        self.assertTrue(.90 < report.within_confidence_fraction < .99)

    def test_calibrated_epipolar_geometry_has_no_metric_scale(self):
        import cv2
        rng = np.random.default_rng(3)
        xyz = np.column_stack([rng.uniform(-2,2,100), rng.uniform(-1,1,100),rng.uniform(5,12,100)])
        k = np.array([[720, 0, 320],[0, 720, 240],[0,0,1]],dtype=float)
        first,_=cv2.projectPoints(xyz,np.zeros(3),np.zeros(3),k,None)
        r = np.array([.02,-.04,.01]);t=np.array([-.7,.1,0])
        second,_=cv2.projectPoints(xyz,r,t,k,None)
        p1=first.reshape(-1,2)+rng.normal(0,.05,(100,2))
        p2=second.reshape(-1,2)+rng.normal(0,.05,(100,2))
        result = recover_motion_from_correspondences(p1,p2,k,minimum_inliers=60)
        self.assertIsNotNone(result)
        self.assertGreater(result.inliers,60)
        self.assertAlmostEqual(np.linalg.norm(result.translation_direction),1.,places=8)
        self.assertGreater(float(result.translation_direction@t/np.linalg.norm(t)),.8)

if __name__ == '__main__':unittest.main()
