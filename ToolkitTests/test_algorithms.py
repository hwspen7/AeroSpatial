"""Algorithm manifests, deterministic plans and compute overload behavior."""
import json
from pathlib import Path
import unittest
import os
import subprocess

from aerospatial_tools.algorithm import AlgorithmManifest, AlgorithmRegistry, load_manifests
from aerospatial_tools.qos import ComputeBudget, ComputePolicy
from aerospatial_tools.workload import WorkloadProfile, replay

ROOT = Path(__file__).resolve().parents[1]


class AlgorithmTests(unittest.TestCase):
    def test_shared_swift_fixture(self):
        registry = load_manifests(ROOT / 'Fixtures/algorithms.json')
        self.assertEqual([m.identifier for m in registry.ordered()],
                         ['object_detector', 'place_indexer'])

    def test_unsafe_outputs_and_types(self):
        source = json.loads((ROOT / 'Fixtures/algorithms.json').read_text())[0]
        for edits in ({'outputs': [1]}, {'outputs': [2]}, {'inputs': [1, 1]},
                      {'memoryBudgetBytes': True}, {'deadlineMilliseconds': 0},
                      {'requiresHardware': 0}):
            with self.subTest(edits=edits), self.assertRaises(ValueError):
                AlgorithmManifest.parse(source | edits)

    def test_missing_cycle_and_duplicate(self):
        source = json.loads((ROOT / 'Fixtures/algorithms.json').read_text())[0]
        first = AlgorithmManifest.parse(source)
        registry = AlgorithmRegistry()
        registry.register(first)
        with self.assertRaises(ValueError):
            registry.register(first)
        registry = AlgorithmRegistry()
        registry.register(AlgorithmManifest.parse(source | {'dependencies': ['unknown']}))
        with self.assertRaises(ValueError):
            registry.ordered()
        registry = AlgorithmRegistry()
        registry.register(AlgorithmManifest.parse(source | {'dependencies': ['other_algorithm']}))
        registry.register(AlgorithmManifest.parse(source | {'identifier': 'other_algorithm',
                                                              'dependencies': ['object_detector']}))
        with self.assertRaises(ValueError):
            registry.ordered()


class ComputeTests(unittest.TestCase):
    def test_rate_pressure_regression(self):
        limiter = ComputeBudget(ComputePolicy(20, 4, 700))
        results = [limiter.admit(0, 3, 0), limiter.admit(0, 2, 0),
                   limiter.admit(50_000_000, 2, 800),
                   limiter.admit(100_000_000, 2, 0),
                   limiter.admit(99_000_000, 1, 0)]
        self.assertEqual(results, ['admitted', 'rate_limited', 'backlogged',
                                   'admitted', 'time_regression'])
        self.assertAlmostEqual(limiter.tokens, 1.0)

    def test_invalid_and_recover(self):
        limiter = ComputeBudget(ComputePolicy(1, 1, 1000))
        self.assertEqual(limiter.admit(0, float('nan'), 0), 'invalid')
        self.assertEqual(limiter.admit(0, 1, 0), 'admitted')
        self.assertEqual(limiter.admit(0, 1, 0), 'rate_limited')
        self.assertEqual(limiter.admit(1_000_000_000, 1, 0), 'admitted')

    def test_native_qos_parity(self):
        path = os.getenv('AEROSPATIAL_QOS_PROBE')
        if not path or not Path(path).is_file():
            self.skipTest('native C++ QoS probe not configured')
        outcomes = subprocess.check_output([path], text=True, timeout=5).splitlines()
        limiter = ComputeBudget(ComputePolicy(20, 4, 700))
        trace = [(0, 3, 0), (0, 2, 0), (50_000_000, 2, 800),
                 (100_000_000, 2, 0), (99_000_000, 1, 0)]
        mapping = {'admitted': '0', 'rate_limited': '1', 'backlogged': '2',
                   'invalid': '3', 'time_regression': '4'}
        expected = [mapping[limiter.admit(*sample)] for sample in trace]
        self.assertEqual(outcomes, expected)

    def test_deterministic_overload_replay(self):
        profile = WorkloadProfile(seed=71, samples=3000)
        first, second = replay(profile), replay(profile)
        self.assertEqual(first, second)
        self.assertTrue(first['counts']['perception']['backlogged'] > 0)
        self.assertTrue(first['counts']['video']['admitted'] > 0)
        for values in first['counts'].values():
            self.assertEqual(sum(values.values()), profile.samples)


if __name__ == '__main__':
    unittest.main()
