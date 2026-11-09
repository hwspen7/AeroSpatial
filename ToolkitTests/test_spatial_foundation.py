import unittest

from aerospatial_tools.calibration import CalibrationRegistry, OpticalCalibration
from aerospatial_tools.tracing import TraceSpan, TraceStore
from aerospatial_tools.qos import ComputeBudget, ComputePolicy
from aerospatial_tools.workload import WorkloadProfile, replay


def calibration(**overrides):
    data = dict(identifier='camera_primary', device='aircraft', camera_frame='optical',
                revision=1, valid_from_ns=0, valid_until_ns=1000, fx=1000, fy=1000,
                cx=500, cy=400, width=1000, height=800,
                camera_to_body_xyzw=(0., 0., 0., 1.),
                translation_body_m=(0., 0., 0.), uncertainty_m=0.2)
    data.update(overrides)
    return OpticalCalibration(**data)


class CalibrationTests(unittest.TestCase):
    def test_strict_validity_boundaries(self):
        store = CalibrationRegistry()
        store.add(calibration())
        self.assertIsNone(store.resolve('aircraft', 'optical', 1000))
        self.assertEqual(store.resolve('aircraft', 'optical', 999).revision, 1)
        store.add(calibration(identifier='camera_next', revision=2,
                              valid_from_ns=1000, valid_until_ns=2000))
        self.assertEqual(store.resolve('aircraft', 'optical', 1000).revision, 2)
        with self.assertRaises(ValueError):
            store.add(calibration(identifier='overlap', valid_from_ns=500,
                                  valid_until_ns=1001))

    def test_invalid_rotation_and_optics(self):
        for item in [dict(camera_to_body_xyzw=(0., 0., 0., 0.)),
                     dict(fx=float('nan')), dict(width=0),
                     dict(uncertainty_m=-1)]:
            with self.subTest(item=item), self.assertRaises(ValueError):
                calibration(**item)

    def test_duplicate_and_capacity(self):
        store = CalibrationRegistry(capacity=1)
        store.add(calibration())
        with self.assertRaises(ValueError):
            store.add(calibration(identifier='other', device='other_device'))


class TraceTests(unittest.TestCase):
    def test_causal_lineage_and_metrics(self):
        trace = TraceStore()
        trace.add(TraceSpan(1, 1, None, 1, 100, 200, 'capture'))
        trace.add(TraceSpan(1, 2, 1, 1, 120, 150, 'decode'))
        self.assertEqual(trace.lineage(1, 2), ('capture', 'decode'))
        self.assertEqual(trace.report()['decode']['median_ns'], 30)
        self.assertEqual(trace.report()['capture']['p95_ns'], 100)

    def test_strict_parent_and_clock_domain(self):
        trace = TraceStore(capacity=1)
        with self.assertRaises(ValueError):
            trace.add(TraceSpan(1, 2, 1, 1, 100, 200, 'decode'))
        trace.add(TraceSpan(1, 1, None, 1, 100, 200, 'capture'))
        with self.assertRaises(ValueError):
            trace.add(TraceSpan(1, 2, 1, 2, 120, 200, 'decode'))
        with self.assertRaises(ValueError):
            TraceSpan(1, 1, None, 1, 200, 100, 'capture')

    def test_duplicate_spans(self):
        trace = TraceStore()
        item = TraceSpan(1, 1, None, 1, 100, 200, 'capture')
        trace.add(item)
        with self.assertRaises(ValueError):
            trace.add(item)


class WorkloadTests(unittest.TestCase):
    def test_fixed_seed_replays_exactly(self):
        profile = WorkloadProfile(seed=42, samples=1000)
        self.assertEqual(replay(profile), replay(profile))
        self.assertLess(replay(profile)['counts']['perception'].get('admitted', 0), 1000)

    def test_rate_limiter_and_clock_rejection(self):
        budget = ComputeBudget(ComputePolicy(10, 2, 800))
        self.assertEqual(budget.admit(0, 2, 0), 'admitted')
        self.assertEqual(budget.admit(0, 1, 0), 'rate_limited')
        self.assertEqual(budget.admit(1_000_000_000, 1, 900), 'backlogged')
        self.assertEqual(budget.admit(100_000_000, 1, 0), 'time_regression')


if __name__ == '__main__':
    unittest.main()
