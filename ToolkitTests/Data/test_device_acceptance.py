"""Physical evidence gate always fails closed when claims are missing."""
import importlib.util
import math
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("device_acceptance", ROOT / "Scripts" / "device-acceptance.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


class DeviceAcceptanceTests(unittest.TestCase):
    def example(self):
        return dict(device_model="DJI Mavic Air 2", ios_version="18.0", dji_sdk_version="4.16.2",
                    aircraft_firmware="1.0.0", physical_device=True, propellers_removed=True,
                    manual_controller_ready=True, sdk_linked=True, sdk_registered=True,
                    verified_mavic_air_2=True, manual_stop_observed=True, disconnect_stopped_video=True,
                    encoded_callbacks=100, complete_access_units=95, decoded_pixel_buffers=94,
                    queue_p95_ms=4, decode_p95_ms=12, decode_p99_ms=20, peak_rss_mb=180,
                    evidence_log_sha256="a" * 64, operator_review="reviewed device capture")

    def test_missing_real_evidence_is_blocked(self):
        self.assertTrue(mod.audit({}))
        self.assertTrue(mod.audit({"simulated": True}))

    def test_explicit_complete_record_passes_structural_gate(self):
        self.assertEqual(mod.audit(self.example()), [])

    def test_negative_and_malformed_metrics_are_blocked(self):
        record = self.example()
        record["decoded_pixel_buffers"] = record["complete_access_units"] + 1
        record["decode_p95_ms"] = float("nan")
        record["physical_device"] = 1
        self.assertGreaterEqual(len(mod.audit(record)), 3)

    def test_unverified_clock_claim_is_blocked(self):
        record = self.example()
        record["camera_capture_clock_verified"] = True
        self.assertTrue(any("uncertainty" in err for err in mod.audit(record)))


if __name__ == "__main__":
    unittest.main()
