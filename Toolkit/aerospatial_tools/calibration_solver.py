"""Measured checkerboard camera calibration; no synthetic/hardcoded device intrinsics.

Object coordinates must be metric checkerboard corner coordinates in the SAME
pattern ordering as the observed image corners for every view.
"""
from __future__ import annotations
from dataclasses import dataclass
import math


@dataclass(frozen=True)
class CameraCalibrationResult:
    camera_matrix: object
    distortion: object
    root_mean_square_reprojection_pixels: float
    view_count: int


def calibrate_from_corners(object_points, image_points, frame_size,
                           *, minimum_views=6, maximum_rms_pixels=3.0) -> CameraCalibrationResult:
    import cv2
    import numpy as np
    if (len(frame_size) != 2 or any(type(x) is not int for x in frame_size) or
        not all(16 <= x <= 16384 for x in frame_size) or
        not 4 <= minimum_views <= 100 or not math.isfinite(maximum_rms_pixels) or
        not 0 < maximum_rms_pixels <= 20 or len(image_points) != len(object_points) or
        not minimum_views <= len(image_points) <= 100):
        raise ValueError('invalid camera calibration data')
    image = []
    obj = []
    for points, uv in zip(object_points, image_points):
        p = np.asarray(points, dtype=np.float32)
        q = np.asarray(uv, dtype=np.float32)
        if (p.ndim != 2 or p.shape[1:] != (3,) or q.shape != (len(p), 2) or
            not 8 <= len(p) <= 2000 or not np.isfinite(p).all() or not np.isfinite(q).all() or
            (q[:, 0] < 0).any() or (q[:, 0] >= frame_size[0]).any() or
            (q[:, 1] < 0).any() or (q[:, 1] >= frame_size[1]).any()):
            raise ValueError('invalid calibration view')
        obj.append(p)
        image.append(q.reshape(-1, 1, 2))
    rms, k, distortion, rotations, translations = cv2.calibrateCamera(
        obj, image, tuple(frame_size), None, None)
    if not np.isfinite(k).all() or not np.isfinite(distortion).all() or (
        not math.isfinite(rms) or rms > maximum_rms_pixels or k[0, 0] <= 0 or k[1, 1] <= 0
    ):
        raise ValueError('calibration did not meet accuracy requirement')
    return CameraCalibrationResult(k, distortion.ravel(), float(rms), len(rotations))
