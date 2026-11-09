"""Fault-isolated trusted offline processor with hard wall-clock timeout.

Runs a separate interpreter; it is NOT a sandbox for untrusted code.
The explicit allowlist controls import entrypoints, not their OS permissions.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import math
import os
import re
import subprocess
import sys
import tempfile

_ENTRY = re.compile(r'^aerospatial_tools\.[a-zA-Z_][a-zA-Z0-9_]*:[a-zA-Z_][a-zA-Z0-9_]*$')


class WorkerFailure(RuntimeError):
    """An offline plugin failed or exceeded an execution budget."""


@dataclass(frozen=True)
class WorkerLimits:
    timeout_seconds: float = 2.0
    maximum_input_bytes: int = 1 << 20
    maximum_output_bytes: int = 1 << 20
    address_space_bytes: int = 0

    def __post_init__(self) -> None:
        if not (math.isfinite(self.timeout_seconds) and 0.01 <= self.timeout_seconds <= 60):
            raise ValueError('invalid deadline')
        if any(type(x) is not int for x in (self.maximum_input_bytes, self.maximum_output_bytes,
                                            self.address_space_bytes)) or not (
            1024 <= self.maximum_input_bytes <= 8 << 20 and
            1024 <= self.maximum_output_bytes <= 8 << 20 and
            (self.address_space_bytes == 0 or 256 << 20 <= self.address_space_bytes <= 8 << 30)
        ):
            raise ValueError('invalid worker resource limit')


class IsolatedAlgorithmWorker:
    def __init__(self, allowed_entries: set[str], limits: WorkerLimits | None = None) -> None:
        if not allowed_entries or any(type(entry) is not str or not _ENTRY.fullmatch(entry)
                                      for entry in allowed_entries):
            raise ValueError('invalid trusted entrypoint allowlist')
        self.allowed_entries = frozenset(allowed_entries)
        self.limits = limits or WorkerLimits()

    def execute(self, entry: str, event: dict) -> dict:
        if entry not in self.allowed_entries:
            raise PermissionError('algorithm is not approved')
        if type(event) is not dict:
            raise ValueError('event must be an object')
        data = json.dumps({'entry': entry, 'event': event}, allow_nan=False,
                          separators=(',', ':')).encode('utf-8')
        if len(data) > self.limits.maximum_input_bytes:
            raise ValueError('input budget exceeded')
        # File-backed stdout prevents unbounded pipe buffering in the parent process.
        with tempfile.TemporaryFile() as stdout:
            cmd = [sys.executable, '-m', 'aerospatial_tools.worker_entry']
            environment = os.environ.copy()
            environment['AEROSPATIAL_WORKER_ADDRESS_SPACE'] = str(self.limits.address_space_bytes)
            environment['AEROSPATIAL_WORKER_OUTPUT_BYTES'] = str(self.limits.maximum_output_bytes)
            try:
                outcome = subprocess.run(cmd, input=data, stdout=stdout,
                                         stderr=subprocess.DEVNULL, check=False,
                                         timeout=self.limits.timeout_seconds, env=environment)
            except subprocess.TimeoutExpired as error:
                raise WorkerFailure('algorithm exceeded wall-clock deadline') from error
            if outcome.returncode != 0:
                raise WorkerFailure('algorithm process failed')
            if stdout.tell() > self.limits.maximum_output_bytes:
                raise WorkerFailure('algorithm exceeded output budget')
            stdout.seek(0)
            try:
                result = json.loads(stdout.read())
            except (ValueError, UnicodeDecodeError) as error:
                raise WorkerFailure('algorithm returned invalid JSON') from error
            if type(result) is not dict or len(result) > 128:
                raise WorkerFailure('algorithm returned invalid object')
            prefix = entry.split(':', 1)[1] + '.'
            # Only namespaced result keys may be merged into an algorithm graph.
            if any(type(k) is not str or not k.startswith(prefix) for k in result):
                raise WorkerFailure('algorithm result namespace violation')
            return result
