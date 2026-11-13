import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from aerospatial_tools.trace_protocol import inspect_trace

ROOT = Path(__file__).resolve().parents[2]


class TraceProtocolTests(unittest.TestCase):
    def test_shared_fixture(self):
        result = inspect_trace(ROOT / 'Fixtures/traces.jsonl')
        self.assertEqual(result['frame_decode']['median_ns'], 1300)
        self.assertEqual(result['object_detect']['count'], 1)

    def test_rejects_missing_parent(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'trace.jsonl'
            example = json.loads((ROOT / 'Fixtures/traces.jsonl').read_text().splitlines()[1])
            path.write_text(json.dumps(example) + '\n')
            with self.assertRaises(ValueError):
                inspect_trace(path)


if __name__ == '__main__':
    unittest.main()
