"""Safety and session-quality integration regression tests."""

import json
import tempfile
import unittest
from pathlib import Path
from aerospatial_tools.audit import audit
from aerospatial_tools.audit_models import Finding
from aerospatial_tools.digest import create_digest, verify_digest
from aerospatial_tools.faults import inject_fault
from aerospatial_tools.privacy import redact_session
from aerospatial_tools.simulation import generate
from aerospatial_tools.validation import validate
from aerospatial_tools.events import read_events


class FoundationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "raw.jsonl"
        generate(self.source, seconds=2, seed=3)

    def test_quality_audit_and_stale_input(self):
        self.assertEqual(audit(self.source).errors, 0)
        bad = self.root / "stale.jsonl"
        inject_fault(self.source, bad, "stale_head")
        self.assertEqual(validate(bad).issue_count, 0)
        self.assertTrue(any(f.code == "command_stale_head" for f in audit(bad).findings))

    def test_validator_detects_corrupted_sequences_and_times(self):
        for fault in ("drop_record", "duplicate_sequence", "clock_regression"):
            damaged = self.root / f"{fault}.jsonl"
            inject_fault(self.source, damaged, fault)
            self.assertGreater(validate(damaged).issue_count, 0)

    def test_private_export_preserves_relative_age(self):
        raw = self.source.read_text()
        self.assertIn('"latitude"', raw)
        clean = self.root / "public.jsonl"
        count = redact_session(self.source, clean)
        self.assertGreater(count, 0)
        sanitized = clean.read_text()
        self.assertNotIn('"latitude"', sanitized)
        self.assertNotIn('"longitude"', sanitized)
        self.assertNotIn('"simulated-00000003"', sanitized)
        self.assertNotIn('"2026-', sanitized)
        self.assertEqual(validate(clean).issue_count, 0)
        self.assertEqual(audit(clean).errors, 0)
        self.assertEqual(list(read_events(clean))[0].uptime, 0)
        with self.assertRaises(ValueError):
            redact_session(self.source, self.source)
        with self.assertRaises(FileExistsError):
            redact_session(self.source, clean)

    def test_digests_detect_corruption(self):
        manifest = self.root / "digest.json"
        create_digest(self.source, manifest)
        self.assertTrue(verify_digest(self.source, manifest))
        with self.source.open("ab") as output:
            output.write(b"\n")
        self.assertFalse(verify_digest(self.source, manifest))

    def test_custom_audit_rule_registration(self):
        class ExampleRule:
            name = "example"

            def inspect(self, events):
                return [Finding("example", "notice", None, str(len(events)))]

        outcome = audit(self.source, rules=(ExampleRule(),))
        self.assertEqual(outcome.errors, 0)
        self.assertEqual(outcome.evaluated_rules, ["example"])
        with self.assertRaises(ValueError):
            audit(self.source, rules=(ExampleRule(), ExampleRule()))
