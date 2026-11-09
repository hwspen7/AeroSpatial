import json
import tempfile
import unittest
from pathlib import Path
from aerospatial_tools.events import InvalidSession, read_events


class EventTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.file = Path(self.temp.name) / "session.jsonl"

    def write(self, **changes):
        raw = {"uptime": 1.0, "kind": "head", "source": "airpods",
               "wallTime": "2026-11-09T00:00:00Z", "fields": {"yaw": 10}}
        raw.update(changes)
        self.file.write_text(json.dumps(raw) + "\n", encoding="utf-8")

    def test_legacy_is_supported(self):
        self.write()
        self.assertEqual(list(read_events(self.file))[0].kind, "head")

    def test_versioned_requires_sequence(self):
        self.write(schemaVersion=1, sessionId="test")
        with self.assertRaises(InvalidSession):
            list(read_events(self.file))

    def test_rejects_non_finite(self):
        self.write(fields={"yaw": float("nan")})
        with self.assertRaises(InvalidSession):
            list(read_events(self.file))

    def test_invalid_line(self):
        self.file.write_text("{bad}\n", encoding="utf-8")
        with self.assertRaisesRegex(InvalidSession, "line 1"):
            list(read_events(self.file))

    def test_rejects_bool_uptime(self):
        self.write(uptime=True)
        with self.assertRaises(InvalidSession):
            list(read_events(self.file))
