import json
import tempfile
import unittest
from pathlib import Path
from aerospatial_tools.validation import validate
from aerospatial_tools.simulation import generate
from aerospatial_tools.analysis import analyze, percentile


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "sample.jsonl"

    def test_synthetic_determinism(self):
        count = generate(self.path, seconds=2, seed=8)
        original = self.path.read_bytes()
        self.assertGreater(count, 10)
        self.assertEqual(validate(self.path).issue_count, 0)
        generate(self.path, seconds=2, seed=8)
        self.assertEqual(self.path.read_bytes(), original)
        report = analyze(self.path)
        self.assertGreater(report.head_samples, 0)
        self.assertGreater(report.gimbal_commands, 0)
        self.assertIsNotNone(report.sensor_to_command_age_ms_p95)

    def test_sequence_gap_and_clock_regression(self):
        generate(self.path, seconds=1)
        events = [json.loads(line) for line in self.path.read_text().splitlines()]
        events[2]["sequence"] += 2
        events[3]["uptime"] = 1
        self.path.write_text("\n".join(json.dumps(event) for event in events) + "\n")
        self.assertGreaterEqual(validate(self.path).issue_count, 2)

    def test_many_seeded_streams_remain_valid(self):
        for seed in range(20):
            generate(self.path, seconds=1, seed=seed,
                     dropout_probability=seed / 25)
            self.assertEqual(validate(self.path).issue_count, 0, f"seed={seed}")

    def test_percentiles(self):
        self.assertIsNone(percentile([], 50))
        self.assertEqual(percentile([0, 10], 50), 5)

    def test_invalid_simulation_options(self):
        with self.assertRaises(ValueError):
            generate(self.path, seconds=-1)
        with self.assertRaises(ValueError):
            generate(self.path, dropout_probability=1.5)
