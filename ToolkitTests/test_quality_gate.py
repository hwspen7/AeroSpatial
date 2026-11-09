import json
import tempfile
import unittest
from pathlib import Path
from aerospatial_tools.quality_gate import QualityThresholds, evaluate
from aerospatial_tools.simulation import generate
from aerospatial_tools.faults import inject_fault


class QualityGateTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.good = self.root / "good.jsonl"
        generate(self.good, seconds=5, seed=42)

    def test_expected_simulation_passes(self):
        thresholds = QualityThresholds(50, 10, 400, 0, 0)
        self.assertTrue(evaluate(self.good, thresholds)["passed"])

    def test_corrupted_and_stale_sessions_are_blocked(self):
        thresholds = QualityThresholds(50, 10, 400, 0, 0)
        for fault in ("drop_record", "stale_head", "clock_regression"):
            target = self.root / f"{fault}.jsonl"
            inject_fault(self.good, target, fault)
            result = evaluate(target, thresholds)
            self.assertFalse(result["passed"])

    def test_bad_threshold_schema_is_rejected(self):
        config = self.root / "profile.json"
        config.write_text(json.dumps({"maximum_semantic_errors": -1}))
        with self.assertRaises(ValueError):
            QualityThresholds.from_file(config)
        config.write_text(json.dumps({"nonexistent": True}))
        with self.assertRaises(ValueError):
            QualityThresholds.from_file(config)
