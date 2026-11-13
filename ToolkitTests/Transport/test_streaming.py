import math
import unittest
from aerospatial_tools.performance import benchmark_stream
from aerospatial_tools.streaming import EventAwareSampler, OnlineMoments, StreamPolicy


class StreamingTests(unittest.TestCase):
    def test_transition_and_safety_event_retained(self):
        sampler = EventAwareSampler(StreamPolicy(0.02, 0.5, 2.0))
        self.assertTrue(sampler.consume(1.0, 0))
        self.assertFalse(sampler.consume(1.01, 0.1))
        self.assertTrue(sampler.consume(1.03, 10))
        self.assertTrue(sampler.consume(1.04, 10, critical=True))
        self.assertTrue(sampler.consume(1.6, 10))
        self.assertEqual(sampler.counters.accepted, 4)
        self.assertEqual(sampler.counters.downsampled, 1)

    def test_invalid_and_nonmonotonic(self):
        sampler = EventAwareSampler()
        self.assertFalse(sampler.consume(float("nan"), 1))
        self.assertTrue(sampler.consume(1, 1))
        self.assertFalse(sampler.consume(0.5, 2))
        self.assertEqual(sampler.counters.invalid, 1)
        self.assertEqual(sampler.counters.backwards, 1)

    def test_moments_and_validation(self):
        moments = OnlineMoments()
        for value in (1, 2, 3):
            moments.add(value)
        self.assertEqual(moments.mean, 2)
        self.assertAlmostEqual(moments.variance, 2/3)
        with self.assertRaises(ValueError):
            moments.add(math.inf)
        with self.assertRaises(ValueError):
            StreamPolicy(minimum_interval=-1)

    def test_benchmark_outputs(self):
        result = benchmark_stream(300, 2)
        self.assertGreater(result["observations_per_second"], 0)
        self.assertGreater(result["retention_fraction"], 0)
        self.assertLessEqual(result["retention_fraction"], 1)


if __name__ == "__main__":
    unittest.main()
