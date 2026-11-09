"""Process isolation, deadlines, quotas, and trusted-plugin boundary."""
from __future__ import annotations
import unittest

from aerospatial_tools.worker import IsolatedAlgorithmWorker, WorkerFailure, WorkerLimits


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.worker = IsolatedAlgorithmWorker({
            'aerospatial_tools.worker_builtin:summarize',
            'aerospatial_tools.worker_builtin:fail',
            'aerospatial_tools.worker_builtin:sleep',
            'aerospatial_tools.worker_builtin:huge',
        }, WorkerLimits(timeout_seconds=3.0, maximum_output_bytes=2048))

    def test_result_in_own_process(self):
        self.assertEqual({'summarize.count': 3, 'summarize.sum': 6},
                         self.worker.execute('aerospatial_tools.worker_builtin:summarize', {'values': [1, 2, 3]}))

    def test_deadline_and_failure_are_isolated(self):
        slow = IsolatedAlgorithmWorker({'aerospatial_tools.worker_builtin:sleep'},
                                       WorkerLimits(timeout_seconds=1.5))
        with self.assertRaises(WorkerFailure):
            slow.execute('aerospatial_tools.worker_builtin:sleep', {})
        with self.assertRaises(WorkerFailure):
            self.worker.execute('aerospatial_tools.worker_builtin:fail', {})
        self.assertEqual(1, self.worker.execute('aerospatial_tools.worker_builtin:summarize',
                                               {'values': [4]})['summarize.count'])

    def test_output_quota_and_allowlist(self):
        with self.assertRaises(WorkerFailure):
            self.worker.execute('aerospatial_tools.worker_builtin:huge', {})
        with self.assertRaises(PermissionError):
            self.worker.execute('os:system', {})

    def test_invalid_input_and_configuration(self):
        with self.assertRaises(ValueError):
            self.worker.execute('aerospatial_tools.worker_builtin:summarize', {'bad': float('nan')})
        with self.assertRaises(ValueError):
            WorkerLimits(timeout_seconds=-1)
        with self.assertRaises(ValueError):
            IsolatedAlgorithmWorker({'malformed'})


if __name__ == '__main__':
    unittest.main()
