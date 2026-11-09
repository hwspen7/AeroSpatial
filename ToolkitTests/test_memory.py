import json
import tempfile
import unittest
from pathlib import Path
from aerospatial_tools.memory_models import Observation
from aerospatial_tools.memory_storage import SpatialMemory
from aerospatial_tools.memory_import import import_markers


class MemoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.database = Path(self.temp.name) / "memory.sqlite3"

    def test_persistence_and_dateline(self):
        with SpatialMemory(self.database) as store:
            entry = Observation.create(0, 179.999, "Pier", "Test only")
            self.assertTrue(store.add(entry))
            self.assertFalse(store.add(entry))
        with SpatialMemory(self.database) as store:
            matches = store.nearby(0, -179.999, radius_meters=300)
            self.assertEqual(len(matches), 1)
            self.assertLess(matches[0][0], 300)

    def test_rejects_invalid_coordinates(self):
        with self.assertRaises(ValueError):
            Observation.create(91, 0, "invalid")
        with self.assertRaises(ValueError):
            Observation.create(1, 0, "")

    def test_marker_import_is_idempotent(self):
        session = Path(self.temp.name) / "recording.jsonl"
        record = {"schemaVersion": 1, "sessionId": "test", "sequence": 0,
                  "uptime": 10, "wallTime": "2026-01-01T00:00:00Z",
                  "kind": "spatial_marker", "source": "app",
                  "fields": {"latitude": 40, "longitude": -83}}
        session.write_text(json.dumps(record) + "\n", encoding="utf-8")
        with SpatialMemory(self.database) as store:
            self.assertEqual(import_markers(session, store), 1)
            self.assertEqual(import_markers(session, store), 0)
            self.assertEqual(len(store.list_observations()), 1)
            self.assertIn("not the geolocation", store.list_observations()[0].note)
