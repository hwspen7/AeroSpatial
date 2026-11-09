import os
from pathlib import Path
import tempfile
import unittest
from aerospatial_tools.retention import RetentionPolicy, plan_retention, apply_retention
from aerospatial_tools.device_replay import FaultProfile, replay_faults


class RetentionTests(unittest.TestCase):
    def test_retention_hold_and_approval(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            old = 1_000_000_000
            for i in range(5):
                file = folder/f'segment-{i:08d}.bin'
                file.write_bytes(bytes([i])*10)
                os.utime(file, ns=(old, old))
            plan = plan_retention(folder, RetentionPolicy(2, 30),
                                  now_ns=old + 40*86400*1_000_000_000,
                                  legal_hold={'segment-00000001.bin'})
            self.assertEqual([r[0] for r in plan.candidates],
                             ['segment-00000000.bin', 'segment-00000002.bin'])
            with self.assertRaises(PermissionError): apply_retention(plan, approval='PURGE:wrong')
            self.assertEqual(apply_retention(plan, approval='PURGE:'+plan.plan_digest), 2)
            self.assertTrue((folder/'segment-00000001.bin').exists())
            self.assertTrue((folder/'segment-00000004.bin').exists())

    def test_tamper_or_symlink_refuses_delete(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for i in range(3):
                file = root/f'segment-{i:08d}.bin'
                file.write_bytes(b'ABC')
                os.utime(file, ns=(1, 1))
            plan = plan_retention(root, RetentionPolicy(1, 0), now_ns=2)
            (root/'segment-00000001.bin').write_bytes(b'DEF')
            with self.assertRaises(ValueError): apply_retention(plan, approval='PURGE:'+plan.plan_digest)
            self.assertTrue((root/'segment-00000000.bin').exists())
            with tempfile.TemporaryDirectory() as other:
                link = root/'segment-00000000.bin'
                link.unlink()
                link.symlink_to(Path(other)/'elsewhere')
                with self.assertRaises(ValueError):
                    plan_retention(root, RetentionPolicy(1, 0), now_ns=2)

class ReplayTests(unittest.TestCase):
    def test_seeded_replay_and_timestamp_provenance(self):
        events = [{'stream': 3, 'timestampNs': i*10000} for i in range(200)]
        policy = FaultProfile(seed=43, dropout_probability=.2, duplicate_probability=.15,
                              jitter_ns=30000)
        a = replay_faults(events, policy)
        b = replay_faults(events, policy)
        self.assertEqual(a, b)
        self.assertGreater(a['dropped'], 0)
        self.assertGreater(a['duplicated'], 0)
        self.assertTrue(all(e['receiveNs'] >= e['timestampNs'] for e in a['events']))
        self.assertEqual([e['receiveNs'] for e in a['events']],
                         sorted(e['receiveNs'] for e in a['events']))
        with self.assertRaises(ValueError):
            replay_faults([events[2], events[1]], policy)
        with self.assertRaises(ValueError):
            FaultProfile(dropout_probability=float('nan'))

if __name__ == '__main__': unittest.main()
