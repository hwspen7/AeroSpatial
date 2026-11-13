"""Synthetic-ground-truth acceptance of optional spatial research algorithms."""
import math
import unittest

try:
    import numpy as np
    import cv2
    import scipy
except ImportError as missing:
    raise unittest.SkipTest("Optional spatial mapping extras unavailable") from missing

import numpy as np
import cv2
from scipy.spatial.transform import Rotation

from aerospatial_tools.visual_geometry import solve_camera_pose, triangulate_observations
from aerospatial_tools.pose_graph import PoseGraph, RelativeEdge
from aerospatial_tools.bundle_adjustment import optimize_bundle, Reprojection
from aerospatial_tools.sparse_map import SparseSpatialMap, Landmark, Keyframe
from aerospatial_tools.calibration_solver import calibrate_from_corners


class SpatialP1Tests(unittest.TestCase):
    def setUp(self):
        self.k = np.array([[580, 0, 320], [0, 585, 240], [0, 0, 1]], dtype=np.float64)
        rng = np.random.default_rng(101)
        self.xyz = np.column_stack([rng.uniform(-1, 1, 30), rng.uniform(-1, 1, 30),
                                    rng.uniform(4, 8, 30)])

    def project(self, xyz, rot, trans):
        projected, _ = cv2.projectPoints(xyz, rot, trans, self.k, None)
        return projected.reshape(-1, 2)

    def test_pnp_metric_pose_and_outlier_rejection(self):
        true_r = np.array([0.08, -0.11, 0.07]);true_t = np.array([.35, -.21, .6])
        rng = np.random.default_rng(33)
        pixels = self.project(self.xyz, true_r, true_t) + rng.normal(0, .3, (30, 2))
        pixels[1] = [100, 400]
        out = solve_camera_pose(self.xyz, pixels, self.k, minimum_inliers=20)
        self.assertIsNotNone(out)
        self.assertGreaterEqual(len(out.inlier_indices), 27)
        self.assertNotIn(1, out.inlier_indices)
        self.assertLess(out.rms_reprojection_pixels, .8)
        self.assertLess(np.linalg.norm(out.translation - true_t), .15)
        self.assertIsNone(solve_camera_pose(self.xyz * [1, 1, 0], pixels, self.k))

    def test_triangulation_rejects_no_parallax_and_behind_camera(self):
        p0 = self.k @ np.c_[np.eye(3), np.zeros(3)]
        p1 = self.k @ np.c_[np.eye(3), [-.7, 0, 0]]
        a = self.project(self.xyz, np.zeros(3), np.zeros(3))
        b = self.project(self.xyz, np.zeros(3), np.array([-.7, 0, 0]))
        got, indices = triangulate_observations(a, b, p0, p1)
        self.assertEqual(len(indices), len(self.xyz))
        self.assertLess(float(np.max(np.linalg.norm(got - self.xyz, axis=1))), 1e-8)
        empty, indices = triangulate_observations(a, a, p0, p0)
        self.assertEqual(len(indices), 0)
        self.assertEqual(len(empty), 0)

    def test_pose_graph_loop_reduces_inconsistent_drift(self):
        g = PoseGraph()
        g.add_pose('0', [0, 0, 0], [0, 0, 0])
        g.add_pose('1', [1.4, .2, .0], [0, 0, .01])
        g.add_pose('2', [2.8, .4, .0], [0, 0, .02])
        g.add_edge(RelativeEdge('0', '1', (1, 0, 0), (0, 0, 0)))
        g.add_edge(RelativeEdge('1', '2', (1, 0, 0), (0, 0, 0)))
        g.add_edge(RelativeEdge('0', '2', (2, 0, 0), (0, 0, 0)))
        solved = g.optimize()
        self.assertTrue(solved.success)
        self.assertAlmostEqual(solved.poses['2'][0][0], 2, places=3)
        self.assertAlmostEqual(solved.poses['2'][0][1], 0, places=3)
        self.assertLess(solved.root_mean_square_normalized_residual, 1e-6)
        disconnected = PoseGraph()
        disconnected.add_pose('0', [0,0,0], [0,0,0]); disconnected.add_pose('1', [1,0,0], [0,0,0])
        disconnected.add_pose('2', [2,0,0], [0,0,0])
        disconnected.add_edge(RelativeEdge('0','1',(1,0,0),(0,0,0)))
        with self.assertRaises(ValueError):disconnected.optimize()

    def test_bundle_adjustment_decreases_reprojection_error(self):
        rng = np.random.default_rng(123)
        true_cameras = np.array([[0, 0, 0, 0, 0, 0], [0, .04, 0, -.6, 0, 0]], dtype=float)
        initial = true_cameras.copy();initial[1] += [.015, -.02, .01, .06, .04, -.02]
        initial_points = self.xyz[:12] + rng.normal(0, .06, (12, 3))
        initial_points[0] = self.xyz[0]  # Independent metric landmark for scale gauge.
        obs = []
        for ci, cam in enumerate(true_cameras):
            pix = self.project(self.xyz[:12], cam[:3], cam[3:])
            pix += rng.normal(0, .15, pix.shape)
            obs.extend(Reprojection(ci, idx, float(p[0]), float(p[1])) for idx, p in enumerate(pix))
        result = optimize_bundle(initial, initial_points, obs, self.k, maximum_iterations=60,
                                 metric_anchor_landmark_index=0)
        self.assertTrue(result.success)
        self.assertLess(result.root_mean_square_pixels, .6)
        self.assertAlmostEqual(result.cameras[0, 3], 0, places=8)
        self.assertTrue(np.allclose(result.landmarks[0], initial_points[0]))
        with self.assertRaises(ValueError):
            optimize_bundle(initial, initial_points, obs, self.k)

    def test_landmark_provenance_and_query(self):
        m = SparseSpatialMap(maximum_landmarks=2, maximum_keyframes=2)
        point = Landmark('A', (1.0, 2.0, 3.0), .2, 'body', 1, 200)
        m.insert_landmark(point)
        m.insert_keyframe(Keyframe('K0', 200, 1, 'calibration-1', ('A',)))
        self.assertEqual(m.nearby((0, 2, 3), 1.1), (point,))
        with self.assertRaises(ValueError):
            m.insert_keyframe(Keyframe('K1', 100, 2, 'calibration-1', ('A',)))
        with self.assertRaises(ValueError):m.insert_landmark(point)

    def test_checkerboard_calibration_from_correspondences(self):
        rng = np.random.default_rng(11)
        object_points = np.float32([[i * .04, j * .04, 0] for j in range(7) for i in range(9)])
        views, corners = [], []
        for i in range(12):
            rv = np.array([-.15 + .034 * i, .11 * math.sin(i), -.07 + .012 * i])
            tv = np.array([-.16 + .02*i, -.10 + .02*i, 1.2 + .05*math.sin(i)])
            uv = self.project(object_points, rv, tv)
            if (uv < 0).any() or (uv[:, 0] >= 640).any() or (uv[:, 1] >= 480).any():
                continue
            views.append(object_points)
            corners.append(uv + rng.normal(0, .05, uv.shape))
        self.assertGreaterEqual(len(views), 6)
        result = calibrate_from_corners(views, corners, (640, 480), maximum_rms_pixels=.5)
        self.assertLess(result.root_mean_square_reprojection_pixels, .5)
        self.assertLess(abs(result.camera_matrix[0,0] - 580), 50)
        self.assertEqual(result.view_count, len(views))

if __name__ == '__main__':
    unittest.main()
