"""Opt-in real decoder and visual geometry tests (require OpenCV and NumPy)."""
from __future__ import annotations
from pathlib import Path
import tempfile
import unittest
from aerospatial_tools.video_source import VideoFileSource, DecodedFrame
from aerospatial_tools.visual_memory import VisualPlaceMemory
from aerospatial_tools.relocalization import VisualRelocalizer

try:
    import cv2
    import numpy as np
    AVAILABLE = True
except ImportError:
    AVAILABLE = False


@unittest.skipUnless(AVAILABLE, 'optional OpenCV and NumPy required')
class VideoVisionTests(unittest.TestCase):
    def image(self):
        rng = np.random.default_rng(42)
        image = np.zeros((480, 640, 3), dtype=np.uint8)
        for x, y in rng.integers([30, 30], [610, 450], size=(170, 2)):
            cv2.circle(image, (int(x), int(y)), int(rng.integers(2, 7)), (255, 255, 255), -1)
        cv2.putText(image, 'SPATIAL', (180, 180), cv2.FONT_HERSHEY_SIMPLEX, 1.4, (255, 255, 255), 2)
        return image

    def test_visual_geometric_match_and_blank_rejection(self):
        image = self.image()
        locator = VisualRelocalizer(minimum_inliers=12)
        locator.register('test-place', image)
        shifted = cv2.warpAffine(image, np.float32([[1, 0, 18], [0, 1, -12]]), (640, 480))
        result = locator.query(shifted)
        self.assertIsNotNone(result)
        self.assertEqual('test-place', result.place_id)
        self.assertGreaterEqual(result.inliers, 20)
        self.assertIsNone(locator.query(np.zeros_like(image)))

    def test_memory_retains_frame_provenance(self):
        image = self.image()
        transformed = cv2.warpAffine(image, np.float32([[1, 0, 8], [0, 1, 7]]), (640, 480))
        memory = VisualPlaceMemory(minimum_inliers=12)
        memory.remember('bridge', DecodedFrame(1, 100000, True, 1000, 640, 480, image))
        evidence = memory.recognize(DecodedFrame(9, 900000, True, 2000, 640, 480, transformed))
        self.assertIsNotNone(evidence)
        self.assertEqual('bridge', evidence.place_id)
        self.assertEqual((1, 9, 900000, 2000),
                         (evidence.reference_frame, evidence.observed_frame,
                          evidence.observed_ns, evidence.uncertainty_ns))

    def test_actual_video_decode_bounds(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.avi'
            writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*'MJPG'), 10, (640, 480))
            self.assertTrue(writer.isOpened())
            for index in range(5):
                frame = self.image()
                cv2.putText(frame, str(index), (20, 120), cv2.FONT_HERSHEY_SIMPLEX,
                            1.2, (255, 255, 255), 2)
                writer.write(frame)
            writer.release()
            decoded = list(VideoFileSource(path).frames())
            self.assertEqual(5, len(decoded))
            self.assertTrue(all(frame.estimated_clock for frame in decoded))
            self.assertTrue(all(frame.uncertainty_ns > 0 for frame in decoded))
            self.assertEqual(sorted(frame.presentation_ns for frame in decoded),
                             [frame.presentation_ns for frame in decoded])
            with self.assertRaises(ValueError):
                list(VideoFileSource(path, maximum_pixels=10).frames())
            with self.assertRaises(OverflowError):
                list(VideoFileSource(path, maximum_frames=3).frames())


if __name__ == '__main__':
    unittest.main()
