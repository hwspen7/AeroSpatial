"""Small-scale reprojection bundle adjustment with two metric gauge anchors.

Camera rotations are Rodrigues vectors; translations are world-to-camera meters.
All pixel observations refer to the same verified pinhole image calibration.
Offline reference implementation only, without real-time guarantees.
"""
from __future__ import annotations
from dataclasses import dataclass
import math


@dataclass(frozen=True)
class Reprojection:
    camera_index: int
    landmark_index: int
    pixel_x: float
    pixel_y: float
    standard_deviation_pixels: float = 1.0


@dataclass(frozen=True)
class BundleSolution:
    cameras: object
    landmarks: object
    root_mean_square_pixels: float
    iterations: int
    success: bool


def optimize_bundle(cameras, landmarks, observations: list[Reprojection], intrinsics, *,
                    maximum_iterations=100, huber_scale=2.0,
                    metric_anchor_landmark_index=None) -> BundleSolution:
    import cv2
    import numpy as np
    from scipy.optimize import least_squares
    cam = np.asarray(cameras, dtype=np.float64)
    xyz = np.asarray(landmarks, dtype=np.float64)
    k = np.asarray(intrinsics, dtype=np.float64)
    if type(metric_anchor_landmark_index) is not int or not 0 <= metric_anchor_landmark_index < len(xyz):
        raise ValueError('a measured fixed metric landmark is required to remove monocular scale ambiguity')
    if cam.ndim != 2 or cam.shape[1:] != (6,) or xyz.ndim != 2 or xyz.shape[1:] != (3,) or (
        not 2 <= len(cam) <= 32 or not 4 <= len(xyz) <= 500 or
        k.shape != (3, 3) or k[0, 0] <= 0 or k[1, 1] <= 0 or
        not np.isfinite(cam).all() or not np.isfinite(xyz).all() or not np.isfinite(k).all() or
        not 10 <= maximum_iterations <= 500 or not math.isfinite(huber_scale) or huber_scale <= 0 or
        not 8 <= len(observations) <= 5000
    ):
        raise ValueError('invalid bundle dimensions')
    camera_ids = np.asarray([v.camera_index for v in observations], dtype=int)
    point_ids = np.asarray([v.landmark_index for v in observations], dtype=int)
    pixels = np.asarray([(v.pixel_x, v.pixel_y) for v in observations])
    sigma = np.asarray([v.standard_deviation_pixels for v in observations])
    if any(type(v.camera_index) is not int or type(v.landmark_index) is not int for v in observations) or (
        (camera_ids < 0).any() or (camera_ids >= len(cam)).any() or
        (point_ids < 0).any() or (point_ids >= len(xyz)).any() or
        not np.isfinite(pixels).all() or not np.isfinite(sigma).all() or
        (sigma <= 0).any() or (sigma > 100).any()
    ):
        raise ValueError('invalid observations')
    if not set(range(len(cam))).issubset(set(camera_ids)) or (
        not set(range(len(xyz))).issubset(set(point_ids))
    ):
        raise ValueError('all cameras/landmarks must be observed')
    # All variables must connect to the known camera and scale-defining landmark.
    for _ in range(len(cam) + len(xyz)):
        if _ == 0:
            visible_cameras, visible_points = {0}, set()
        for c, p in zip(camera_ids, point_ids):
            if int(c) in visible_cameras: visible_points.add(int(p))
            if int(p) in visible_points: visible_cameras.add(int(c))
    if len(visible_cameras) != len(cam) or len(visible_points) != len(xyz):
        raise ValueError('disconnected observations')
    origin_cam = cam[0].copy()
    fixed_point = xyz[metric_anchor_landmark_index].copy()
    variable_points = [index for index in range(len(xyz)) if index != metric_anchor_landmark_index]
    def unpack(flat):
        remaining = (len(cam) - 1) * 6
        poses = np.vstack([origin_cam, flat[:remaining].reshape(-1, 6)])
        points = np.empty_like(xyz)
        points[metric_anchor_landmark_index] = fixed_point
        points[variable_points] = flat[remaining:].reshape(-1, 3)
        return poses, points
    def residual(flat):
        poses, points = unpack(flat)
        errors = np.empty((len(observations), 2), dtype=float)
        for i in range(len(poses)):
            rows = np.flatnonzero(camera_ids == i)
            proj, _ = cv2.projectPoints(points[point_ids[rows]], poses[i, :3],
                                        poses[i, 3:].reshape(3, 1), k, None)
            errors[rows] = (proj.reshape(-1, 2) - pixels[rows]) / sigma[rows, None]
        return errors.ravel()
    x0 = np.r_[cam[1:].ravel(), xyz[variable_points].ravel()]
    result = least_squares(residual, x0, loss='huber', f_scale=huber_scale,
                           max_nfev=maximum_iterations)
    refined_cam, refined_xyz = unpack(result.x)
    if not np.isfinite(refined_cam).all() or not np.isfinite(refined_xyz).all():
        raise ValueError('divergent bundle')
    # A solved bundle must preserve positive camera depth for all used observations.
    for i, camera in enumerate(refined_cam):
        rotation, _ = cv2.Rodrigues(camera[:3])
        rows = np.flatnonzero(camera_ids == i)
        depths = (rotation @ refined_xyz[point_ids[rows]].T + camera[3:, None])[2]
        if np.any(depths <= 0):
            raise ValueError('estimated landmarks behind camera')
    # Report actual pixel-space error, independent of the declared weight.
    weighted_errors = residual(result.x).reshape(-1, 2) * sigma[:, None]
    rms = float(np.sqrt(np.mean(np.sum(weighted_errors ** 2, axis=1))))
    return BundleSolution(refined_cam, refined_xyz, rms, result.nfev, bool(result.success))
