"""Cross-language verification against the compiled C++ geodesy tool."""

import json
import os
import subprocess
import unittest
from aerospatial_tools.memory_query import great_circle_meters


class NativeParityTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("AEROSPATIAL_NATIVE_PROBE"), "native executable not configured")
    def test_cpp_python_geodesy(self):
        binary = os.environ["AEROSPATIAL_NATIVE_PROBE"]
        examples = [(0, 0, 0, .001), (0, 179.999, 0, -179.999),
                    (40.0, -83.0, 40.002, -83.003), (-75, 20, -74.99, 20.001)]
        for lat1, lon1, lat2, lon2 in examples:
            response = subprocess.run([binary, "geo", *(str(x) for x in
                                   (lat1, lon1, lat2, lon2))], check=True,
                                   text=True, capture_output=True)
            cpp = json.loads(response.stdout)
            py = great_circle_meters(lat1, lon1, lat2, lon2)
            self.assertAlmostEqual(cpp["distance_m"], py, delta=1e-6)
