import os
from pathlib import Path
import subprocess
import unittest
from aerospatial_tools.wire import encode_head, decode_head

class WireTests(unittest.TestCase):
    def test_cpp_python_wire_parity(self):
        probe = os.environ.get('AEROSPATIAL_WIRE_PROBE')
        if not probe:
            self.skipTest('native wire probe not supplied')
        result = subprocess.check_output([str(Path(probe).resolve())], text=True).strip()
        self.assertEqual(result, encode_head(12.25, 10, -20, 5).hex())

    def test_round_trip_and_corruption(self):
        data = encode_head(12.25, 10, -20, 5)
        self.assertEqual(len(data), 44)
        self.assertEqual(decode_head(data), (12.25, 10, -20, 5))
        with self.assertRaises(ValueError):
            decode_head(data[:-1])
        damaged = bytearray(data)
        damaged[16] ^= 1
        with self.assertRaises(ValueError):
            decode_head(bytes(damaged))
        with self.assertRaises(ValueError):
            encode_head(float('nan'), 0, 0, 0)
