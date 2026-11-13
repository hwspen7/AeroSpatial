import json
import os
import subprocess
import unittest
from pathlib import Path
from aerospatial_tools.frames import ecef, enu


class ReferenceFrameParityTests(unittest.TestCase):
    def setUp(self):
        self.probe = Path(os.environ.get("AEROSPATIAL_NATIVE_PROBE", "build-native/aerospatial-native-probe"))
        if not self.probe.is_file():
            self.skipTest("native probe not built")

    def call(self, mode, *values):
        result = subprocess.run([str(self.probe), mode, *map(str, values)],
                                capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_ellipsoidal_positions_near_poles_and_dateline(self):
        for p in ((0, 0, 0), (40, -83, 250), (89.999, 179.999, 500), (-30, -179.999, -80)):
            actual = self.call("ecef", *p)
            expected = ecef(*p)
            for axis, reference in zip(("x", "y", "z"), expected):
                self.assertAlmostEqual(actual[axis], reference, delta=1e-4)
        for a, b in (((0, 179.999, 0), (0, -179.999, 0)),
                     ((40, -83, 250), (40.001, -82.999, 270))):
            actual = self.call("enu", *a, *b)
            expected = enu(a, b)
            for axis, reference in zip(("east", "north", "up"), expected):
                self.assertAlmostEqual(actual[axis], reference, delta=1e-4)

    def test_rejects_invalid_coordinates(self):
        with self.assertRaises(ValueError):
            ecef(99, 0, 0)
