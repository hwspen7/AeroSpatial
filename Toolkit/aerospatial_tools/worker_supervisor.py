"""Explicit trusted-worker lifecycle for optional offline algorithms only.

The worker executes a pre-approved Python function, not the model artifact.
The catalog is used to gate deployment readiness and detect changed artifacts.
This is not hostile-code sandboxing or physical-device inference.
"""
from __future__ import annotations
from dataclasses import dataclass

from .model_catalog import ModelArtifact, ModelCatalog
from .worker import IsolatedAlgorithmWorker, WorkerFailure


@dataclass
class WorkerStatus:
    state: str = 'unregistered'
    attempts: int = 0
    successful: int = 0
    failed: int = 0
    consecutive_failures: int = 0


class TrustedWorkerSupervisor:
    def __init__(self, catalog: ModelCatalog, worker: IsolatedAlgorithmWorker,
                 *, failure_limit: int = 3):
        if type(failure_limit) is not int or not 1 <= failure_limit <= 100:
            raise ValueError('invalid failure threshold')
        self.catalog = catalog
        self.worker = worker
        self.failure_limit = failure_limit
        self.status = WorkerStatus()
        self.artifact: ModelArtifact | None = None
        self.entry: str | None = None

    def deploy(self, artifact: ModelArtifact, entry: str, *, backends: set[str],
               maximum_memory_bytes: int, maximum_latency_ms: float) -> None:
        if self.status.state == 'ready':
            raise ValueError('worker must be stopped before redeployment')
        if entry not in self.worker.allowed_entries:
            raise PermissionError('unapproved code entrypoint')
        match = self.catalog.choose(artifact.identifier, available_backends=backends,
                                    maximum_memory_bytes=maximum_memory_bytes,
                                    maximum_latency_ms=maximum_latency_ms)
        if match != artifact:
            raise ValueError('model is not a verified supported deployment')
        self.artifact = artifact
        self.entry = entry
        self.status = WorkerStatus(state='ready')

    def execute(self, event: dict) -> dict:
        if self.status.state != 'ready' or self.artifact is None or self.entry is None:
            raise WorkerFailure('offline worker not ready')
        self.status.attempts += 1
        try:
            if not self.catalog.verify(self.artifact):
                raise WorkerFailure('deployed artifact changed since verification')
            result = self.worker.execute(self.entry, event)
        except (WorkerFailure, OSError, ValueError) as error:
            self.status.failed += 1
            self.status.consecutive_failures += 1
            if self.status.consecutive_failures >= self.failure_limit:
                self.status.state = 'quarantined'
            raise WorkerFailure('trusted optional worker failed') from error
        self.status.successful += 1
        self.status.consecutive_failures = 0
        return result

    def stop(self) -> None:
        self.status.state = 'stopped'

    def reset(self) -> None:
        # Explicit operator action required to leave quarantine.
        self.status.state = 'stopped'
        self.status.consecutive_failures = 0
