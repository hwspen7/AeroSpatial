"""Authenticated local export of sensitive observation data (optional dependency).

The caller owns key lifecycle. Never store an encryption key in source control.
This is file confidentiality/integrity, not a substitute for app permissions.
"""
from __future__ import annotations
from pathlib import Path
import os
import tempfile

from .access import AccessPolicy

_MAGIC = b'ASVAULT\x01'
_AAD = b'AeroSpatial.authenticated-export.1'
_MAX_PLAINTEXT = 64 * 1024 * 1024


def _cipher(key: bytes):
    if type(key) is not bytes or len(key) != 32:
        raise ValueError('AES-256 requires a 32-byte key')
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError as error:
        raise RuntimeError('install aerospatial-tools[privacy] for AES-GCM support') from error
    return AESGCM(key)


def encrypt(payload: bytes, key: bytes) -> bytes:
    if type(payload) is not bytes or not 0 < len(payload) <= _MAX_PLAINTEXT:
        raise ValueError('invalid export size')
    nonce = os.urandom(12)
    return _MAGIC + nonce + _cipher(key).encrypt(nonce, payload, _AAD)


def decrypt(blob: bytes, key: bytes) -> bytes:
    if type(blob) is not bytes or not (len(_MAGIC) + 12 + 16 < len(blob) <=
                                      _MAX_PLAINTEXT + len(_MAGIC) + 12 + 16):
        raise ValueError('invalid vault container')
    if not blob.startswith(_MAGIC):
        raise ValueError('unsupported vault format')
    try:
        return _cipher(key).decrypt(blob[len(_MAGIC):len(_MAGIC) + 12],
                                    blob[len(_MAGIC) + 12:], _AAD)
    except Exception as error:
        raise ValueError('authentication failed') from error


def export_encrypted(source: Path, target: Path, key: bytes, policy: AccessPolicy, *,
                     purpose: str, stream: str, now_ns: int) -> None:
    if not policy.permits(purpose, stream, now_ns):
        raise PermissionError('export grant missing or expired')
    source, target = Path(source), Path(target)
    if source.resolve() == target.resolve():
        raise ValueError('cannot encrypt in place')
    if not source.is_file() or source.stat().st_size > _MAX_PLAINTEXT:
        raise ValueError('source missing or exceeds limit')
    encrypted = encrypt(source.read_bytes(), key)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        # Temp file permissions 0600; hard-link commits without clobbering a racing writer.
        descriptor, path = tempfile.mkstemp(prefix='.aerospatial-', dir=target.parent)
        temporary = Path(path)
        with os.fdopen(descriptor, 'wb') as out:
            out.write(encrypted)
            out.flush()
            os.fsync(out.fileno())
        os.link(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
