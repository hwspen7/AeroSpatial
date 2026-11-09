"""Validated metric loop edges. Image appearance alone is insufficient evidence.

The caller must independently measure/estimate an SE(3) relative pose (e.g. PnP)
and retain its calibration/version and inlier evidence. This module enforces
conservative gates before adding an edge to the bounded pose graph.
"""
from __future__ import annotations
from dataclasses import dataclass
import math
from .pose_graph import PoseGraph, RelativeEdge


@dataclass(frozen=True)
class MetricLoopEvidence:
    first_frame: str
    second_frame: str
    frame_separation: int
    calibration_id: str
    geometric_inliers: int
    geometric_inlier_ratio: float
    translation_first_m: tuple[float,float,float]
    rotation_first_to_second: tuple[float,float,float]
    position_std_m: float
    angle_std_rad: float
    capture_time_uncertainty_ms: float


class LoopClosureValidator:
    def __init__(self, *, minimum_inliers=20, minimum_ratio=.65,
                 minimum_frame_separation=10, maximum_time_uncertainty_ms=25):
        if (minimum_inliers<8 or not 0<minimum_ratio<=1 or minimum_frame_separation<1 or
            not 0<maximum_time_uncertainty_ms<=1000):
            raise ValueError('invalid loop gate policy')
        self.minimum_inliers=minimum_inliers
        self.minimum_ratio=minimum_ratio
        self.minimum_frame_separation=minimum_frame_separation
        self.maximum_time_uncertainty_ms=maximum_time_uncertainty_ms

    def accept(self, evidence:MetricLoopEvidence, graph:PoseGraph) -> bool:
        if (evidence.first_frame == evidence.second_frame or
            evidence.first_frame not in graph.nodes or evidence.second_frame not in graph.nodes or
            not evidence.calibration_id or evidence.geometric_inliers<self.minimum_inliers or
            not math.isfinite(evidence.geometric_inlier_ratio) or
            evidence.geometric_inlier_ratio<self.minimum_ratio or
            evidence.frame_separation<self.minimum_frame_separation or
            not math.isfinite(evidence.capture_time_uncertainty_ms) or
            evidence.capture_time_uncertainty_ms>self.maximum_time_uncertainty_ms or
            not 0<evidence.position_std_m<=100 or not 0<evidence.angle_std_rad<=3):
            return False
        edge=RelativeEdge(evidence.first_frame,evidence.second_frame,evidence.translation_first_m,
                          evidence.rotation_first_to_second,evidence.position_std_m,evidence.angle_std_rad)
        try:graph.add_edge(edge)
        except ValueError:return False
        return True
