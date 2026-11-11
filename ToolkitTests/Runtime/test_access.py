import unittest
from aerospatial_tools.access import AccessPolicy, Grant


class AccessPolicyTests(unittest.TestCase):
    def test_default_deny_and_expiry(self):
        policy = AccessPolicy((Grant('analysis', frozenset({'telemetry', 'head'}), 100),))
        self.assertTrue(policy.permits('analysis', 'head', 99))
        self.assertFalse(policy.permits('analysis', 'head', 100))
        self.assertFalse(policy.permits('share', 'telemetry', 1))
        self.assertFalse(policy.permits('analysis', 'video', 1))
        self.assertFalse(policy.permits('analysis', 'head', True))

    def test_invalid_grants_rejected(self):
        with self.assertRaises(ValueError):
            Grant('invalid', frozenset({'head'}), 5)
        with self.assertRaises(ValueError):
            Grant('share', frozenset({'unknown'}), 5)


if __name__ == '__main__':
    unittest.main()
