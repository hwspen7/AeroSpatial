"""Reproducible full-path metric fixture, without access to aircraft or GPS."""
import unittest

try:
    import numpy
    import cv2
    import scipy
except ImportError as missing:
    raise unittest.SkipTest('Optional spatial mapping extras unavailable') from missing

from aerospatial_tools.spatial_demo import run


class SpatialCliP1Tests(unittest.TestCase):
    def test_fixed_seed_is_reproducible(self):
        result = run(seed=42)
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result, run(seed=42))
        self.assertEqual(result['triangulated_landmarks'], 12)
        self.assertLess(result['pnp_translation_error_m'], .1)

    def test_invalid_seed_is_rejected(self):
        with self.assertRaises(ValueError):
            run(seed=-1)

if __name__ == '__main__': unittest.main()
