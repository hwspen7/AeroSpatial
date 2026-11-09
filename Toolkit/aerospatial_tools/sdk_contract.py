"""Portable, pure-data PoseStamped adapter for ROS 2 integration.

No rclpy dependency. No aircraft connection. ROS timestamps must be explicitly
supplied as wall/simulation clock time; raw monotonic timestamps are rejected.
"""
from __future__ import annotations
from dataclasses import dataclass
from math import isfinite, sqrt
import re

_FRAME = re.compile(r'^[a-zA-Z][a-zA-Z0-9_/-]{0,63}$')


@dataclass(frozen=True)
class VerifiedPose:
    frame_id: str
    stamp_ros_ns: int
    position_xyz_m: tuple[float, float, float]
    quaternion_xyzw: tuple[float, float, float, float]
    source_trace_id: int
    calibrated: bool

    def __post_init__(self):
        if (type(self.frame_id) is not str or not _FRAME.fullmatch(self.frame_id) or
            self.frame_id.startswith('/')):
            raise ValueError('invalid ROS frame identifier')
        if (type(self.stamp_ros_ns) is not int or not 0 <= self.stamp_ros_ns < 2**63 or
            type(self.source_trace_id) is not int or not 0 <= self.source_trace_id < 2**63 or
            self.calibrated is not True):
            raise ValueError('unverified pose or missing ROS timestamp')
        if (len(self.position_xyz_m) != 3 or len(self.quaternion_xyzw) != 4 or
            any(not isfinite(v) for v in self.position_xyz_m + self.quaternion_xyzw)):
            raise ValueError('invalid pose values')
        norm = sqrt(sum(x*x for x in self.quaternion_xyzw))
        if abs(norm - 1) > 1e-5:
            raise ValueError('non-unit quaternion')


def pose_stamped(pose: VerifiedPose) -> dict:
    x, y, z = pose.position_xyz_m
    qx, qy, qz, qw = pose.quaternion_xyzw
    return {'header': {
                'stamp': {'sec': pose.stamp_ros_ns // 1_000_000_000,
                          'nanosec': pose.stamp_ros_ns % 1_000_000_000},
                'frame_id': pose.frame_id},
            'pose': {'position': {'x': x, 'y': y, 'z': z},
                     'orientation': {'x': qx, 'y': qy, 'z': qz, 'w': qw}}}
