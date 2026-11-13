import unittest
try:
    import numpy as np
    import cv2
    import scipy
except ImportError as missing:
    raise unittest.SkipTest("Optional spatial mapping extras unavailable") from missing

import numpy as np
from aerospatial_tools.uncertainty import camera_ray_with_covariance,rigid_point_with_covariance
from aerospatial_tools.motion_models import MotionPredictor
from aerospatial_tools.pose_graph import PoseGraph
from aerospatial_tools.loop_closure import MetricLoopEvidence,LoopClosureValidator


class SpatialQualityTests(unittest.TestCase):
    def test_analytic_ray_jacobian_matches_finite_differences(self):
        k=np.array([[500,0,320],[0,480,240],[0,0,1]])
        uv=np.array([470.,270.])
        ray,cov,j=camera_ray_with_covariance(uv,k,np.eye(2))
        self.assertAlmostEqual(np.linalg.norm(ray),1,places=12)
        self.assertTrue(np.linalg.eigvalsh(cov).min()>-1e-15)
        for dimension in range(2):
            perturbed=uv.copy();perturbed[dimension]+=.001
            ray2,_,_=camera_ray_with_covariance(perturbed,k,np.eye(2))
            self.assertTrue(np.allclose((ray2-ray)/.001,j[:,dimension],atol=1e-7))

    def test_rigid_point_uncertainty_includes_rotation(self):
        result,cov=rigid_point_with_covariance([1,0,0],np.eye(3),[2,0,0],
                                               np.eye(6)*.02,np.eye(3)*.1)
        self.assertTrue(np.allclose(result,[3,0,0]))
        self.assertGreater(cov[1,1],cov[0,0])
        self.assertTrue(np.linalg.eigvalsh(cov).min()>0)

    def test_cv_and_ca_forecast(self):
        linear=MotionPredictor();accelerated=MotionPredictor()
        for i in range(20):
            t=i*.1
            linear.append(t,[2*t,3*t,0])
            accelerated.append(t,[1.5*t*t,0,0])
        predicted=linear.forecast(2.2)
        self.assertIsNotNone(predicted)
        self.assertEqual(predicted.selected_model,'constant_velocity')
        self.assertAlmostEqual(predicted.position_m[0],4.4,places=5)
        got=accelerated.forecast(2.2)
        self.assertEqual(got.selected_model,'constant_acceleration')
        self.assertAlmostEqual(got.position_m[0],1.5*2.2**2,places=4)
        self.assertIsNone(linear.forecast(9))
        with self.assertRaises(ValueError):linear.append(1,[0,0,0])

    def test_loop_closure_requires_calibrated_metric_evidence(self):
        g=PoseGraph();g.add_pose('first',[0,0,0],[0,0,0]);g.add_pose('second',[1,0,0],[0,0,0])
        check=LoopClosureValidator()
        e=MetricLoopEvidence('first','second',20,'calibration-c7',30,.8,(1,0,0),
                             (0,0,0),.5,.05,5)
        self.assertTrue(check.accept(e,g))
        self.assertEqual(len(g.edges),1)
        bad=MetricLoopEvidence('first','second',20,'calibration-c7',30,.2,(1,0,0),
                             (0,0,0),.5,.05,5)
        self.assertFalse(check.accept(bad,g))
        self.assertEqual(len(g.edges),1)

if __name__=='__main__':unittest.main()
