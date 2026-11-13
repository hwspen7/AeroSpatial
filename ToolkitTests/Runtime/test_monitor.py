import unittest
from aerospatial_tools.monitor import RuntimeMonitor

class MonitorTests(unittest.TestCase):
    def test_histogram_memory_and_quality_gate(self):
        monitor = RuntimeMonitor()
        for i in range(100):
            monitor.record(receive_ns=i*1_000_000, latency_ns=400_000,
                           live_bytes=i*32, dropped=int(i == 9))
        report = monitor.report()
        self.assertEqual(report['p99_upper_us'], 500)
        self.assertEqual(report['max_live_bytes'], 3168)
        monitor.enforce(max_live_bytes=4000, max_p99_us=600, max_drop_fraction=.02)
        with self.assertRaises(RuntimeError):
            monitor.enforce(max_live_bytes=2000, max_p99_us=600, max_drop_fraction=.02)
        with self.assertRaises(ValueError):
            monitor.record(receive_ns=0, latency_ns=1, live_bytes=0)
