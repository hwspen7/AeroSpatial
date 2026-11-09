import tempfile
import unittest
from pathlib import Path
from aerospatial_tools.perception_models import FrameObservation, ImageBox
from aerospatial_tools.perception_store import PerceptionStore


class PerceptionStoreTests(unittest.TestCase):
    def test_evidence_is_idempotent_queryable_and_not_geolocation(self):
        with tempfile.TemporaryDirectory() as folder:
            database = Path(folder) / "perception.sqlite3"
            observation = FrameObservation.create("s1", "frame-001", 123.4,
                "demo-model-0", "car", 0.91, ImageBox(0.1, 0.2, 0.3, 0.4))
            with PerceptionStore(database) as store:
                self.assertTrue(store.add(observation))
                self.assertFalse(store.add(observation))
                different = FrameObservation.create("s1", "frame-002", 124,
                    "demo-model-0", "tree", 0.8, ImageBox(0.1, 0.1, 0.2, 0.3),
                    identifier=observation.identifier)
                with self.assertRaises(ValueError):
                    store.add(different)
                self.assertEqual(store.by_label("car"), [observation])
                self.assertEqual(store.by_session("s1"), [observation])
                self.assertEqual(store.by_session("missing"), [])
            with PerceptionStore(database) as reopened:
                self.assertEqual(reopened.by_label("car"), [observation])
            self.assertNotIn("latitude", str(observation))

    def test_rejects_bad_box_and_confidence(self):
        for args in ((0.9, 0.1, 0.2, 0.2), (0.1, -0.1, 0.2, 0.2),
                     (0.1, 0.1, 0, 0.3)):
            with self.assertRaises(ValueError):
                ImageBox(*args)
        with self.assertRaises(ValueError):
            FrameObservation.create("s1", "f", 1, "model", "object", 1.4,
                                    ImageBox(0, 0, 0.2, 0.2))
        with self.assertRaises(ValueError):
            FrameObservation("id", "s1", "f", 1, "model", "object", 0.5,
                             ImageBox(0, 0, 0.2, 0.2), coordinate_frame="world")
        with self.assertRaises(ValueError):
            FrameObservation.create("s1", "f", float("nan"), "model", "object", 0.5,
                                    ImageBox(0, 0, 0.2, 0.2))
