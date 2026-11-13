"""Two-phase, fail-closed retention for *derived* copies of archived sessions.

Never run on live recording directories, flight evidence, or an unreviewed path.
The caller explicitly acknowledges a hash of the exact deletion plan.
"""
from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import stat

_SEGMENT = re.compile(r'^segment-[0-9]{8}\.bin$')


@dataclass(frozen=True)
class RetentionPolicy:
    minimum_keep: int = 2
    minimum_age_seconds: int = 30 * 86400
    def __post_init__(self):
        if (type(self.minimum_keep) is not int or not 1 <= self.minimum_keep <= 10000 or
            type(self.minimum_age_seconds) is not int or not 0 <= self.minimum_age_seconds <= 10**10):
            raise ValueError('invalid retention policy')


@dataclass(frozen=True)
class RetentionPlan:
    root: Path
    candidates: tuple[tuple[str, int, str], ...]  # filename, inode, digest
    plan_digest: str


def _snapshot(file: Path) -> tuple[int, str, int]:
    info = file.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise ValueError('non-regular, linked or hard-linked segment')
    digest = sha256()
    with file.open('rb') as stream:
        if os.fstat(stream.fileno()).st_ino != info.st_ino:
            raise ValueError('segment changed during snapshot')
        while chunk := stream.read(1 << 20):
            digest.update(chunk)
        current = os.fstat(stream.fileno())
    if (current.st_size, current.st_mtime_ns) != (info.st_size, info.st_mtime_ns):
        raise ValueError('segment changed during hashing')
    return info.st_ino, digest.hexdigest(), info.st_mtime_ns


def _hash_plan(root: Path, records: tuple[tuple[str, int, str], ...]) -> str:
    data = json.dumps([str(root), records], separators=(',', ':')).encode()
    return sha256(data).hexdigest()


def plan_retention(root: Path, policy: RetentionPolicy, *, now_ns: int,
                   legal_hold: set[str] | None = None) -> RetentionPlan:
    if type(now_ns) is not int or now_ns < 0 or root.is_symlink():
        raise ValueError('invalid retention clock or directory')
    absolute = root.resolve(strict=True)
    if not absolute.is_dir():
        raise ValueError('archive root must be a directory')
    names = sorted(entry.name for entry in absolute.iterdir() if _SEGMENT.fullmatch(entry.name))
    held = legal_hold or set()
    if not all(_SEGMENT.fullmatch(name) for name in held):
        raise ValueError('illegal hold identity')
    candidates = []
    for name in names[:-policy.minimum_keep]:
        if name in held:
            continue
        inode, digest, modified_ns = _snapshot(absolute / name)
        if modified_ns <= now_ns and now_ns - modified_ns >= policy.minimum_age_seconds * 1_000_000_000:
            candidates.append((name, inode, digest))
    result = tuple(candidates)
    return RetentionPlan(absolute, result, _hash_plan(absolute, result))


def apply_retention(plan: RetentionPlan, *, approval: str) -> int:
    if approval != 'PURGE:' + plan.plan_digest:
        raise PermissionError('retention requires exact explicit plan approval')
    if plan.root.is_symlink() or not plan.root.is_dir() or not plan.candidates:
        return 0
    # Validate ALL candidates before deleting anything; reject any changed data.
    for name, inode, digest in plan.candidates:
        if not _SEGMENT.fullmatch(name):
            raise ValueError('invalid retention target')
        check_inode, check_digest, _ = _snapshot(plan.root / name)
        if check_inode != inode or check_digest != digest:
            raise ValueError('archive changed since retention plan')
    # A privileged filesystem process could still race these checks. Retention
    # must be run on a private directory with no concurrent writers.
    for name, _inode, _digest in plan.candidates:
        (plan.root / name).unlink()
    return len(plan.candidates)
