import unittest

from aerospatial_tools.trace_gate import StageLimit, assess_stages


class TraceGateTests(unittest.TestCase):
    def test_pass_and_missing_stage_fail_closed(self):
        data = {'decode': {'count': 20, 'p95_ns': 100, 'errors': 0}}
        limit = StageLimit(10, 150, 0.1)
        self.assertTrue(assess_stages(data, {'decode': limit})['passed'])
        self.assertEqual(assess_stages(data, {'inference': limit})['findings'][0]['reason'], 'missing')

    def test_detects_latency_and_quality_regression(self):
        data = {'detect': {'count': 10, 'p95_ns': 900, 'errors': 3}}
        report = assess_stages(data, {'detect': StageLimit(10, 800, 0.1)})
        self.assertFalse(report['passed'])
        self.assertEqual({item['reason'] for item in report['findings']},
                         {'latency_exceeded', 'error_fraction_exceeded'})

    def test_rejects_bad_limits_and_insufficient_samples(self):
        with self.assertRaises(ValueError):
            StageLimit(0, 100, 0.5)
        result = assess_stages({'step': {'count': 2}}, {'step': StageLimit(3, 100, 0.2)})
        self.assertFalse(result['passed'])


if __name__ == '__main__':
    unittest.main()
