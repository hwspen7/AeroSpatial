"""Optional, observation-only ROS 2 PoseStamped publishing adapter.

Requires a caller-owned initialized rclpy node and geometry_msgs at runtime.
Never publishes commands and never assumes the AeroSpatial monotonic clock is
already ROS wall/simulation time. Only explicit VerifiedPose is accepted.
"""
from __future__ import annotations
import re

from .sdk_contract import VerifiedPose, pose_stamped

_TOPIC = re.compile(r'^/[A-Za-z][A-Za-z0-9_/]{0,127}$')


class ROSPosePublisher:
    def __init__(self, node, *, topic: str = '/aerospatial/observed_pose', depth: int = 10):
        if (type(topic) is not str or not _TOPIC.fullmatch(topic) or
            '//' in topic or topic.endswith('/') or
            type(depth) is not int or not 1 <= depth <= 1000):
            raise ValueError('invalid observation topic or QoS depth')
        try:
            from geometry_msgs.msg import PoseStamped
        except ImportError as error:
            raise RuntimeError('ROS 2 geometry_msgs must be installed') from error
        self._type = PoseStamped
        self._publisher = node.create_publisher(PoseStamped, topic, depth)
        self.topic = topic

    def publish(self, pose: VerifiedPose) -> None:
        if type(pose) is not VerifiedPose:
            raise TypeError('only explicitly calibrated, ROS-timestamped poses may be published')
        value = pose_stamped(pose)
        message = self._type()
        message.header.frame_id = value['header']['frame_id']
        message.header.stamp.sec = value['header']['stamp']['sec']
        message.header.stamp.nanosec = value['header']['stamp']['nanosec']
        p = value['pose']['position']
        q = value['pose']['orientation']
        for name in ('x', 'y', 'z'):
            setattr(message.pose.position, name, p[name])
        for name in ('x', 'y', 'z', 'w'):
            setattr(message.pose.orientation, name, q[name])
        self._publisher.publish(message)
