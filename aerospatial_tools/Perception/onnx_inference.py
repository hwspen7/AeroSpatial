"""Real, CPU-only OpenCV DNN inference of verified trusted ONNX artifacts.

This is bounded *offline* inference, not an iPhone Core ML runner, a model
sandbox, a true hard deadline, or a flight-control component.
"""
from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from math import isfinite
from time import perf_counter_ns

from .model_catalog import ModelArtifact, ModelCatalog


@dataclass(frozen=True)
class InferenceSummary:
    model_id: str
    revision: str
    runtime: str
    elapsed_ns: int
    output_shape: tuple[int, ...]
    output_sha256: str
    output_minimum: float
    output_maximum: float


class VerifiedONNXRunner:
    def __init__(self, catalog: ModelCatalog, artifact: ModelArtifact, *,
                 channels: int, height: int, width: int,
                 max_output_elements: int = 1_000_000,
                 maximum_inference_ms: float = 1000.0):
        if (artifact.backend != 'onnx' or
            type(channels) is not int or channels not in (1, 3) or
            type(height) is not int or type(width) is not int or
            not 1 <= height <= 4096 or not 1 <= width <= 4096 or
            height * width > 4096 * 2160 or
            type(max_output_elements) is not int or not 1 <= max_output_elements <= 20_000_000 or
            not isfinite(maximum_inference_ms) or not 1 <= maximum_inference_ms <= 60000):
            raise ValueError('invalid trusted ONNX deployment limits')
        if not catalog.verify(artifact):
            raise ValueError('model digest mismatch')
        if artifact.memory_bytes < channels * height * width * 4:
            raise ValueError('input exceeds declared model memory budget')
        try:
            import cv2
        except ImportError as error:
            raise RuntimeError('OpenCV DNN is required for ONNX CPU inference') from error
        self._cv2 = cv2
        try:
            self._net = cv2.dnn.readNetFromONNX(str(catalog._file(artifact)))
        except cv2.error as error:
            raise ValueError('ONNX model cannot be loaded') from error
        self._net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
        self._net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)
        self._catalog = catalog
        self._artifact = artifact
        self._shape = (channels, height, width)
        self._output_limit = max_output_elements
        self._deadline_ns = int(maximum_inference_ms * 1_000_000)

    def infer_video_frame(self, decoded_bgr_image) -> tuple[object, InferenceSummary]:
        """Convert an actual OpenCV-decoded BGR frame to the model input contract."""
        import numpy as np
        channels, height, width = self._shape
        if (type(decoded_bgr_image) is not np.ndarray or
            decoded_bgr_image.dtype != np.uint8 or decoded_bgr_image.ndim != 3 or
            decoded_bgr_image.shape[2] != 3 or
            not 1 <= decoded_bgr_image.shape[0] <= 4096 or
            not 1 <= decoded_bgr_image.shape[1] <= 4096):
            raise ValueError('invalid decoded BGR video frame')
        resized = self._cv2.resize(decoded_bgr_image, (width, height))
        image = (self._cv2.cvtColor(resized, self._cv2.COLOR_BGR2GRAY) if channels == 1
                 else self._cv2.cvtColor(resized, self._cv2.COLOR_BGR2RGB))
        return self.infer(image)

    def infer(self, image) -> tuple[object, InferenceSummary]:
        """Return the actual float32 ONNX output, plus provenance metrics."""
        import numpy as np
        channels, height, width = self._shape
        if (type(image) is not np.ndarray or image.dtype != np.uint8 or
            image.shape != ((height, width) if channels == 1 else (height, width, channels))):
            raise ValueError('input image must match the declared uint8 HWC layout')
        if not self._catalog.verify(self._artifact):
            raise ValueError('ONNX artifact changed after deployment')
        # Avoid OpenCV changing normalization semantics when inputs are grayscale.
        blob = image.astype(np.float32) / 255.0
        if channels == 1:
            blob = blob.reshape(1, 1, height, width)
        else:
            blob = np.ascontiguousarray(blob.transpose(2, 0, 1)[None])
        started = perf_counter_ns()
        try:
            self._net.setInput(blob)
            output = self._net.forward()
        except self._cv2.error as error:
            raise RuntimeError('ONNX inference failed') from error
        elapsed = perf_counter_ns() - started
        if elapsed > self._deadline_ns:
            raise TimeoutError('ONNX inference exceeded observed deadline')
        if (not isinstance(output, np.ndarray) or output.size > self._output_limit or
            output.nbytes > self._artifact.memory_bytes or not np.all(np.isfinite(output))):
            raise ValueError('ONNX output exceeds budget or contains non-finite values')
        values = np.ascontiguousarray(output.astype(np.float32, copy=False))
        summary = InferenceSummary(
            model_id=self._artifact.identifier, revision=self._artifact.revision,
            runtime='opencv-dnn-cpu', elapsed_ns=elapsed,
            output_shape=tuple(values.shape),
            output_sha256=sha256(values.tobytes()).hexdigest(),
            output_minimum=float(values.min()), output_maximum=float(values.max()))
        return values, summary
