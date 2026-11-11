"""Authenticated export, tampering, access expiry and overwrite protection."""
from __future__ import annotations
import os
from pathlib import Path
import tempfile
import unittest
from aerospatial_tools.access import AccessPolicy, Grant
from aerospatial_tools.vault import encrypt, decrypt, export_encrypted

try:
    import cryptography
    AVAILABLE = True
except ImportError:
    AVAILABLE = False


@unittest.skipUnless(AVAILABLE, 'cryptography optional dependency required')
class VaultTests(unittest.TestCase):
    def test_authentication_and_size(self):
        key = os.urandom(32)
        blob = encrypt(b'{"location":"private"}', key)
        self.assertEqual(b'{"location":"private"}', decrypt(blob, key))
        with self.assertRaises(ValueError):
            decrypt(blob, os.urandom(32))
        corrupted = bytearray(blob)
        corrupted[-1] ^= 0x01
        with self.assertRaises(ValueError):
            decrypt(bytes(corrupted), key)
        with self.assertRaises(ValueError):
            encrypt(b'', key)
        with self.assertRaises(ValueError):
            encrypt(b'hello', b'short')

    def test_default_deny_expiry_and_exclusive_create(self):
        with tempfile.TemporaryDirectory() as d:
            source, target = Path(d) / 'private.jsonl', Path(d) / 'record.asvault'
            source.write_text('confidential flight data')
            key = os.urandom(32)
            with self.assertRaises(PermissionError):
                export_encrypted(source, target, key, AccessPolicy(),
                                 purpose='analysis', stream='telemetry', now_ns=5)
            policy = AccessPolicy((Grant('analysis', frozenset({'telemetry'}), 10),))
            with self.assertRaises(PermissionError):
                export_encrypted(source, target, key, policy,
                                 purpose='analysis', stream='telemetry', now_ns=10)
            export_encrypted(source, target, key, policy,
                             purpose='analysis', stream='telemetry', now_ns=5)
            self.assertEqual(source.read_bytes(), decrypt(target.read_bytes(), key))
            self.assertNotIn(b'confidential', target.read_bytes())
            with self.assertRaises(FileExistsError):
                export_encrypted(source, target, key, policy,
                                 purpose='analysis', stream='telemetry', now_ns=5)
            self.assertEqual('confidential flight data', source.read_text())


if __name__ == '__main__':
    unittest.main()
