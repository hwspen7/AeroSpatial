import contextlib
from io import StringIO
import json
from pathlib import Path
import unittest

from aerospatial_tools.cli import main

ROOT = Path(__file__).resolve().parents[1]


class AlgorithmCliTests(unittest.TestCase):
    def command(self, *arguments):
        output = StringIO()
        with contextlib.redirect_stdout(output):
            status = main(list(arguments))
        return status, json.loads(output.getvalue())

    def test_algorithm_plan(self):
        status, result = self.command('algorithms', str(ROOT / 'Fixtures/algorithms.json'))
        self.assertEqual(status, 0)
        self.assertEqual(result['executionOrder'], ['object_detector', 'place_indexer'])

    def test_trace_audit(self):
        status, result = self.command('trace-audit', str(ROOT / 'Fixtures/traces.jsonl'))
        self.assertEqual(status, 0)
        self.assertEqual(result['frame_ingress']['count'], 1)

    def test_deterministic_workload(self):
        status, result = self.command('workload', '--samples', '500', '--seed', '9')
        self.assertEqual(status, 0)
        self.assertEqual(result['samples_per_stream'], 500)
        self.assertEqual(result['seed'], 9)


if __name__ == '__main__':
    unittest.main()
