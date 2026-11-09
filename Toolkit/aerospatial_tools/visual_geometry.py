"""Calibrated image geometry, with explicit scale/depth and degeneracy limitations.

All results are offline measurements. Visual odometry's translation has *unknown scale*.
Matrices use OpenCV's world-to-camera convention; image coordinates are pixels.
"""
from __future__ import annotations
from dataclasses import dataclass
import math


@dataclass(frozen=True)
class RelativeMotion:
    rotation: object
    translation_direction: object
    inliers: int
    tentative_matches: int
    median_epipolar_error: float


@dataclass(frozen=True)
class CameraPose:
    rotation: object
    translation: object
    inlier_indices: tuple[int, ...]
    rms_reprojection_pixels: float


def _camera_matrix(camera):
    import numpy as np
    k = np.asarray(camera, dtype=np.float64)
    if k.shape != (3, 3) or not np.isfinite(k).all() or k[0, 0] <= 0 or k[1, 1] <= 0 or (
        not np.allclose(k[2], [0, 0, 1], atol=1e-12)
    ):
        raise ValueError('invalid intrinsic matrix')
    return k


def _points(points, dimensions, *, minimum=0, maximum=20000):
    import numpy as np
    p = np.asarray(points, dtype=np.float64)
    if p.ndim != 2 or p.shape[1] != dimensions or not minimum <= len(p) <= maximum or not np.isfinite(p).all():
        raise ValueError('invalid point observations')
    return p


def estimate_relative_motion(first_image, second_image, camera, *, minimum_inliers=25,
                             reprojection_threshold=1.0, maximum_features=1200) -> RelativeMotion | None:
    """ORB + ratio matching + essential matrix RANSAC, independent of video backend.

    Requires calibrated (preferably undistorted) images, nonzero translational parallax
    and static-scene texture. A successful result is not metric odometry.
    """
    import cv2
    import numpy as np
    k = _camera_matrix(camera)
    if not 8 <= minimum_inliers <= 10000 or not 64 <= maximum_features <= 5000 or (
        not math.isfinite(reprojection_threshold) or not .01 <= reprojection_threshold <= 10
    ):
        raise ValueError('invalid matching policy')
    first, second = np.asarray(first_image), np.asarray(second_image)
    if first.ndim not in (2, 3) or second.ndim != first.ndim or first.shape != second.shape or (
        first.dtype != np.uint8 or second.dtype != np.uint8 or first.size > 8192 * 8192 * 4
    ):
        raise ValueError('images must have matching uint8 shapes')
    orb = cv2.ORB_create(nfeatures=maximum_features)
    kp1, desc1 = orb.detectAndCompute(first, None)
    kp2, desc2 = orb.detectAndCompute(second, None)
    if desc1 is None or desc2 is None or len(kp1) < minimum_inliers:
        return None
    matches = cv2.BFMatcher(cv2.NORM_HAMMING).knnMatch(desc1, desc2, k=2)
    good = [a for pair in matches if len(pair) == 2 for a, b in [pair]
            if a.distance < .72 * b.distance]
    if len(good) < minimum_inliers:
        return None
    p1 = np.float64([kp1[x.queryIdx].pt for x in good])
    p2 = np.float64([kp2[x.trainIdx].pt for x in good])
    return recover_motion_from_correspondences(p1, p2, k, minimum_inliers=minimum_inliers,
                                                reprojection_threshold=reprojection_threshold,
                                                tentative_count=len(good))


def recover_motion_from_correspondences(first_points, second_points, camera, *,
                                        minimum_inliers=12, reprojection_threshold=1.0,
                                        tentative_count=None) -> RelativeMotion | None:
    """Calibrated epipolar geometry from independently verified pixel correspondences.

    The translation unit vector has NO metric scale; planar/rotation-only scenes
    can be degenerate. A robust estimate is a hypothesis, not a full VO trajectory.
    """
    import cv2
    import numpy as np
    k = _camera_matrix(camera)
    p1 = _points(first_points, 2, minimum=8)
    p2 = _points(second_points, 2, minimum=8)
    if (len(p1) != len(p2) or not 8 <= minimum_inliers <= len(p1) or
        not math.isfinite(reprojection_threshold) or not .01 <= reprojection_threshold <= 10):
        raise ValueError('invalid epipolar inputs')
    cv2.setRNGSeed(42)
    e, inlier = cv2.findEssentialMat(p1, p2, k, method=cv2.RANSAC,
                                     prob=.999, threshold=reprojection_threshold)
    if e is None or inlier is None or e.shape != (3, 3):
        return None
    count, rotation, translation, pose_mask = cv2.recoverPose(e, p1, p2, k, mask=inlier)
    if count < minimum_inliers or rotation is None or translation is None or (
        not np.isfinite(rotation).all() or not np.isfinite(translation).all()
    ):
        return None
    normalized1 = cv2.undistortPoints(p1.reshape(-1, 1, 2), k, None).reshape(-1, 2)
    normalized2 = cv2.undistortPoints(p2.reshape(-1, 1, 2), k, None).reshape(-1, 2)
    h1 = np.column_stack([normalized1, np.ones(len(p1))])
    h2 = np.column_stack([normalized2, np.ones(len(p2))])
    residual = np.abs(np.einsum('ni,ij,nj->n', h2, e, h1))
    used = pose_mask.ravel() > 0
    return RelativeMotion(rotation, translation.reshape(3), int(count),
                          int(tentative_count if tentative_count is not None else len(p1)),
                          float(np.median(residual[used])))


def solve_camera_pose(world_points, image_points, camera, *, minimum_inliers=6,
                      reprojection_threshold=3.0) -> CameraPose | None:
    """RANSAC PnP from known metric 3D landmarks; returns world-to-camera pose."""
    import cv2
    import numpy as np
    xyz = _points(world_points, 3, minimum=6)
    uv = _points(image_points, 2, minimum=6)
    k = _camera_matrix(camera)
    if len(xyz) != len(uv) or not 6 <= minimum_inliers <= len(xyz) or (
        not math.isfinite(reprojection_threshold) or not .1 <= reprojection_threshold <= 50
    ):
        raise ValueError('invalid PnP policy')
    # Fail closed on fully collinear or coplanar degenerate input for general 3D PnP.
    if np.linalg.matrix_rank(xyz - xyz.mean(axis=0), tol=1e-8) < 3:
        return None
    cv2.setRNGSeed(42)
    good, rv, tv, inliers = cv2.solvePnPRansac(
        xyz, uv, k, None, flags=cv2.SOLVEPNP_EPNP, iterationsCount=500,
        reprojectionError=reprojection_threshold, confidence=.999)
    if not good or inliers is None or len(inliers) < minimum_inliers:
        return None
    indices = inliers.reshape(-1)
    rv, tv = cv2.solvePnPRefineLM(xyz[indices], uv[indices], k, None, rv, tv)
    return _finish_pose(xyz, uv, k, indices, rv, tv)


def _finish_pose(xyz, uv, k, indices, rv, tv) -> CameraPose | None:
    import cv2
    import numpy as np
    if not np.isfinite(rv).all() or not np.isfinite(tv).all():
        return None
    rotation, _ = cv2.Rodrigues(rv)
    camera_points = (rotation @ xyz[indices].T + tv.reshape(3, 1)).T
    if np.any(camera_points[:, 2] <= 0):
        return None
    projected, _ = cv2.projectPoints(xyz[indices], rv, tv, k, None)
    differences = projected.reshape(-1, 2) - uv[indices]
    rms = float(np.sqrt(np.mean(np.sum(differences * differences, axis=1))))
    return CameraPose(rotation, tv.reshape(3), tuple(int(i) for i in indices), rms)


def triangulate_observations(first_points, second_points, projection_first,
                             projection_second, *, maximum_reprojection_error=2.0,
                             minimum_parallax_degrees=1.0):
    """Metric triangulation, requiring two verified calibrated camera matrices.

    Returns a tuple of reconstructed xyz and valid-input indices. Both projection
    matrices must use the SAME world scale and a consistent 3D reference frame.
    """
    import cv2
    import numpy as np
    a = _points(first_points, 2, minimum=1)
    b = _points(second_points, 2, minimum=1)
    p1 = np.asarray(projection_first, dtype=np.float64)
    p2 = np.asarray(projection_second, dtype=np.float64)
    if len(a) != len(b) or p1.shape != (3, 4) or p2.shape != (3, 4) or (
        not np.isfinite(p1).all() or not np.isfinite(p2).all() or
        not math.isfinite(maximum_reprojection_error) or maximum_reprojection_error <= 0 or
        not .01 <= minimum_parallax_degrees < 90
    ):
        raise ValueError('invalid triangulation inputs')
    centers = []
    for p in (p1, p2):
        _, _, vh = np.linalg.svd(p)
        center = vh[-1]
        if abs(center[3]) < 1e-12:
            return np.empty((0, 3)), tuple()
        centers.append(center[:3] / center[3])
    if np.linalg.norm(centers[1] - centers[0]) < 1e-8:
        return np.empty((0, 3)), tuple()
    homogeneous = cv2.triangulatePoints(p1, p2, a.T, b.T)
    valid = np.abs(homogeneous[3]) > 1e-10
    xyz = np.zeros((len(a), 3), dtype=np.float64)
    xyz[valid] = (homogeneous[:3, valid] / homogeneous[3, valid]).T
    accepted = []
    for i, x in enumerate(xyz):
        if not valid[i] or not np.isfinite(x).all() or (
            (p1 @ np.r_[x, 1])[2] <= 0 or (p2 @ np.r_[x, 1])[2] <= 0
        ):
            continue
        rays = [x - c for c in centers]
        cos_angle = np.dot(*rays) / (np.linalg.norm(rays[0]) * np.linalg.norm(rays[1]))
        angle = math.degrees(math.acos(float(np.clip(cos_angle, -1, 1))))
        if angle < minimum_parallax_degrees:
            continue
        projections = [p @ np.r_[x, 1] for p in (p1, p2)]
        if max(np.linalg.norm(q[:2] / q[2] - uv) for q, uv in zip(projections, (a[i], b[i]))) > maximum_reprojection_error:
            continue
        accepted.append(i)
    return xyz[accepted], tuple(accepted)
