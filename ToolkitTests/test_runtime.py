import unittest
import time
from pathlib import Path

from aerospatial_tools.algorithm import load_manifests
from aerospatial_tools.runtime import AlgorithmRuntime

ROOT = Path(__file__).resolve().parents[1]


def registry():
    return load_manifests(ROOT / 'Fixtures/algorithms.json')


class AlgorithmRuntimeTests(unittest.TestCase):
    def test_deterministic_dependency_outputs(self):
        instance = AlgorithmRuntime(registry())
        instance.bind('object_detector', lambda data: {'object_detector.count': 3})
        instance.bind('place_indexer', lambda data: {'place_indexer.count': data['object_detector.count']})
        result = instance.execute(0, {'trace': 42})
        self.assertEqual(result['status'], {'object_detector': 'ok', 'place_indexer': 'ok'})
        self.assertEqual(result['context']['place_indexer.count'], 3)
        self.assertEqual(result['context']['trace'], 42)

    def test_exception_isolation_quarantine_and_recovery(self):
        instance = AlgorithmRuntime(registry(), failure_limit=2)
        def broken(data):
            raise RuntimeError('failure')
        instance.bind('object_detector', broken)
        instance.bind('place_indexer', lambda data: {'place_indexer.result': True})
        first = instance.execute(0, {})
        self.assertEqual(first['status']['place_indexer'], 'blocked')
        second = instance.execute(1_000_000_000, {})
        self.assertEqual(second['status']['object_detector'], 'failed')
        self.assertTrue(instance.stats['object_detector'].quarantined)
        third = instance.execute(2_000_000_000, {})
        self.assertEqual(third['status']['object_detector'], 'blocked')
        instance.clear_quarantine('object_detector')
        self.assertFalse(instance.stats['object_detector'].quarantined)

    def test_invalid_output_does_not_spoof_source_data(self):
        instance = AlgorithmRuntime(registry(), failure_limit=1)
        instance.bind('object_detector', lambda data: {'trace': 999})
        instance.bind('place_indexer', lambda data: {'place_indexer.result': 1})
        result = instance.execute(0, {'trace': 10})
        self.assertEqual(result['status']['object_detector'], 'failed')
        self.assertEqual(result['context']['trace'], 10)
        self.assertEqual(result['status']['place_indexer'], 'blocked')
        self.assertTrue(instance.stats['object_detector'].quarantined)

    def test_deadline_and_output_budget_fail_closed(self):
        instance = AlgorithmRuntime(registry(), failure_limit=1)
        instance.bind('object_detector', lambda data: (time.sleep(0.13) or {'object_detector.value': 1}))
        instance.bind('place_indexer', lambda data: {})
        result = instance.execute(0, {})
        self.assertEqual(result['status']['object_detector'], 'failed')
        self.assertEqual(instance.stats['object_detector'].over_deadline, 1)
        self.assertEqual(result['status']['place_indexer'], 'blocked')

    def test_pressure_rejection_does_not_run_processor(self):
        instance = AlgorithmRuntime(registry())
        calls = []
        instance.bind('object_detector', lambda data: calls.append('called') or {})
        instance.bind('place_indexer', lambda data: {})
        result = instance.execute(0, {}, pressure=1000)
        self.assertEqual(calls, [])
        self.assertEqual(result['status']['object_detector'], 'backlogged')


if __name__ == '__main__':
    unittest.main()
