"""Content-addressed, read-only model selection for trusted local deployments.

SHA-256 verifies bytes but does not establish who published a model. Execution and
OS sandboxing are deliberately outside this catalog.
"""
from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path
import re

_ID = re.compile(r'^[a-z][a-z0-9_-]{2,63}$')
_REVISION = re.compile(r'^[0-9]+\.[0-9]+\.[0-9]+$')
_DIGEST = re.compile(r'^[0-9a-f]{64}$')
_BACKENDS = frozenset({'coreml', 'onnx', 'tflite', 'native'})


@dataclass(frozen=True)
class ModelArtifact:
    identifier: str
    revision: str
    backend: str
    relative_path: str
    sha256: str
    memory_bytes: int
    typical_latency_ms: float
    input_stream: int
    output_stream: int

    def __post_init__(self) -> None:
        from math import isfinite
        if (type(self.identifier) is not str or type(self.revision) is not str or
            not _ID.fullmatch(self.identifier) or not _REVISION.fullmatch(self.revision)):
            raise ValueError('invalid model identity or revision')
        if self.backend not in _BACKENDS or type(self.relative_path) is not str or not self.relative_path:
            raise ValueError('invalid model runtime or filename')
        path = Path(self.relative_path)
        if path.is_absolute() or len(path.parts) != 1 or path.name in {'.', '..'}:
            raise ValueError('model path must be one filename under the catalog root')
        if type(self.sha256) is not str or not _DIGEST.fullmatch(self.sha256):
            raise ValueError('invalid content hash')
        if (type(self.memory_bytes) is not int or not 1 <= self.memory_bytes <= 8 << 30 or
            not isfinite(self.typical_latency_ms) or not 0 < self.typical_latency_ms <= 60000 or
            type(self.input_stream) is not int or self.input_stream not in range(1, 6) or
            type(self.output_stream) is not int or self.output_stream not in (4, 5)):
            raise ValueError('invalid model resources or stream contract')


class ModelCatalog:
    def __init__(self, root: Path, maximum_models: int = 256):
        if not 1 <= maximum_models <= 10000:
            raise ValueError('invalid model count')
        self.root = root.resolve(strict=True)
        if not self.root.is_dir():
            raise ValueError('model root must be a directory')
        self.maximum_models = maximum_models
        self._models: dict[tuple[str, str], ModelArtifact] = {}

    def _file(self, artifact: ModelArtifact) -> Path:
        location = self.root / artifact.relative_path
        if location.is_symlink() or not location.is_file() or location.resolve(strict=True).parent != self.root:
            raise ValueError('missing, linked or unsafe model file')
        return location

    def verify(self, artifact: ModelArtifact) -> bool:
        location = self._file(artifact)
        digest = sha256()
        with location.open('rb') as stream:
            while chunk := stream.read(1 << 20):
                digest.update(chunk)
        return digest.hexdigest() == artifact.sha256

    def add(self, artifact: ModelArtifact) -> None:
        key = artifact.identifier, artifact.revision
        if key in self._models or len(self._models) >= self.maximum_models:
            raise ValueError('duplicate or over-capacity model')
        if not self.verify(artifact):
            raise ValueError('model digest mismatch')
        self._models[key] = artifact

    def choose(self, identifier: str, *, available_backends: set[str],
               maximum_memory_bytes: int, maximum_latency_ms: float) -> ModelArtifact | None:
        # A deployment is rejected if the bytes have changed since registration.
        from math import isfinite
        if (not _ID.fullmatch(identifier) or not available_backends <= _BACKENDS or
            type(maximum_memory_bytes) is not int or maximum_memory_bytes < 0 or
            not isfinite(maximum_latency_ms) or maximum_latency_ms < 0):
            raise ValueError('invalid deployment conditions')
        candidates = [m for m in self._models.values() if m.identifier == identifier and
                      m.backend in available_backends and m.memory_bytes <= maximum_memory_bytes and
                      m.typical_latency_ms <= maximum_latency_ms and self.verify(m)]
        # Prefer lower measured latency, then lower memory, then revision.
        return min(candidates, key=lambda m: (m.typical_latency_ms, m.memory_bytes, m.revision),
                   default=None)
