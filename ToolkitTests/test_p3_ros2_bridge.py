"""Contract tests use a fake ROS node; no ROS installation is claimed."""
from __future__ import annotations
from types import ModuleType, SimpleNamespace
from unittest.mock import patch
import sys
import unittest

from aerospatial_tools.sdk_contract import VerifiedPose
from aerospatial_tools.ros2_bridge import ROSPosePublisher


class Published:
    def __init__(self):
        self.items = []

    def publish(self, item):
        self.items.append(item)


class Node:
    def __init__(self):
        self.publisher = Published()
        self.args = None

    def create_publisher(self, *args):
        self.args = args
        return self.publisher


def message():
    return SimpleNamespace(
        header=SimpleNamespace(frame_id='', stamp=SimpleNamespace(sec=0, nanosec=0)),
        pose=SimpleNamespace(position=SimpleNamespace(), orientation=SimpleNamespace()))


class ROSBridgeContractTests(unittest.TestCase):
    def test_observation_only_with_explicit_ros_clock(self):
        node = Node()
        root = ModuleType('geometry_msgs')
        module = ModuleType('geometry_msgs.msg')
        module.PoseStamped = message
        root.msg = module
        with patch.dict(sys.modules, {'geometry_msgs': root, 'geometry_msgs.msg': module}):
            bridge = ROSPosePublisher(node, topic='/aerospatial/test', depth=5)
            pose = VerifiedPose('map', 1_700_000_000_123_000_000,
                                (1, 2, 3), (0, 0, 0, 1), 7, True)
            bridge.publish(pose)
            item = node.publisher.items[0]
            self.assertEqual(item.header.frame_id, 'map')
            self.assertEqual(item.header.stamp.sec, 1_700_000_000)
            self.assertEqual(item.header.stamp.nanosec, 123_000_000)
            self.assertEqual(item.pose.position.x, 1)
            self.assertEqual(item.pose.orientation.w, 1)
            self.assertEqual(node.args[-1], 5)
            with self.assertRaises(TypeError):
                bridge.publish({'unverified': True})

    def test_reject_unsafe_topic_or_bad_depth(self):
        with self.assertRaises(ValueError):
            ROSPosePublisher(Node(), topic='/commands/../flight')
        with self.assertRaises(ValueError):
            ROSPosePublisher(Node(), depth=0)


if __name__ == '__main__':
    unittest.main()
