"""Actual ONNX forward pass with a minimal verified Relu graph."""
from __future__ import annotations
from hashlib import sha256
from pathlib import Path
import tempfile
import unittest

try:
    import cv2
    import numpy as np
except ImportError:
    cv2 = None

from aerospatial_tools.model_catalog import ModelArtifact, ModelCatalog
from aerospatial_tools.onnx_inference import VerifiedONNXRunner


def _varint(n):
    result = bytearray()
    while n >= 128:
        result.append((n & 127) | 128)
        n >>= 7
    result.append(n)
    return bytes(result)


def _integer(tag, value):
    return _varint(tag << 3) + _varint(value)


def _bytes(tag, payload):
    return _varint(tag << 3 | 2) + _varint(len(payload)) + payload


def _string(tag, value):
    return _bytes(tag, value.encode('utf-8'))


def tiny_relu_onnx() -> bytes:
    """Serialize a standard ONNX graph using simple protobuf fields, no onnx dependency."""
    shape = b''.join(_bytes(1, _integer(1, dimension)) for dimension in (1, 1, 2, 2))
    tensor_type = _bytes(1, _integer(1, 1) + _bytes(2, shape))
    value = lambda name: _string(1, name) + _bytes(2, tensor_type)
    node = _string(1, 'input') + _string(2, 'output') + _string(4, 'Relu')
    graph = (_bytes(1, node) + _string(2, 'aerospatial_test') +
             _bytes(11, value('input')) + _bytes(12, value('output')))
    return (_integer(1, 8) + _string(2, 'AeroSpatial') +
            _bytes(7, graph) + _bytes(8, _integer(2, 13)))


@unittest.skipUnless(cv2 is not None, 'optional OpenCV and NumPy required')
class ONNXIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.model_path = self.root / 'tiny.onnx'
        self.model_path.write_bytes(tiny_relu_onnx())
        self.catalog = ModelCatalog(self.root)
        self.artifact = ModelArtifact('tiny-relu', '1.0.0', 'onnx', 'tiny.onnx',
            sha256(self.model_path.read_bytes()).hexdigest(),
            64 * 1024, 1000.0, 3, 4)
        self.catalog.add(self.artifact)

    def test_real_cpu_onnx_forward_is_numerically_correct(self):
        runner = VerifiedONNXRunner(self.catalog, self.artifact,
                                    channels=1, width=2, height=2)
        data = np.array([[0, 64], [128, 255]], dtype=np.uint8)
        result, summary = runner.infer(data)
        np.testing.assert_allclose(result[0, 0], data / 255.0, atol=1e-6)
        self.assertEqual(summary.runtime, 'opencv-dnn-cpu')
        self.assertEqual(summary.output_shape, (1, 1, 2, 2))
        self.assertEqual(summary.model_id, 'tiny-relu')
        self.assertEqual(len(summary.output_sha256), 64)

    def test_modified_artifact_is_rejected_before_inference(self):
        runner = VerifiedONNXRunner(self.catalog, self.artifact, channels=1, width=2, height=2)
        self.model_path.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed'):
            runner.infer(np.zeros((2, 2), dtype=np.uint8))

    def test_malformed_image_and_output_resource_limits_are_rejected(self):
        runner = VerifiedONNXRunner(self.catalog, self.artifact, channels=1, width=2, height=2)
        with self.assertRaises(ValueError):
            runner.infer(np.zeros((3, 3), dtype=np.uint8))
        with self.assertRaises(ValueError):
            runner.infer(np.ones((2, 2), dtype=np.float32))
        small = VerifiedONNXRunner(self.catalog, self.artifact,
                                   channels=1, width=2, height=2, max_output_elements=3)
        with self.assertRaisesRegex(ValueError, 'output exceeds'):
            small.infer(np.ones((2, 2), dtype=np.uint8))

    def test_real_video_decoding_model_inference_and_spatial_evidence_are_integrated(self):
        from aerospatial_tools.evidence_pipeline import EvidencePipelineConfig, index_video_evidence
        from aerospatial_tools.spatial_evidence import SpatialEvidenceStore
        video = self.root / 'scene.avi'
        writer = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*'MJPG'),
                                 20, (192, 160))
        if not writer.isOpened():
            self.skipTest('MJPEG video writer unavailable')
        rng = np.random.default_rng(42)
        image = rng.integers(0, 255, (160, 192, 3), dtype=np.uint8)
        for _ in range(12):
            writer.write(image)
        writer.release()
        runner = VerifiedONNXRunner(self.catalog, self.artifact,
                                    channels=1, width=2, height=2)
        db = self.root / 'spatial.sqlite3'
        result = index_video_evidence(
            video, video, db, session='testflight', place_label='siteA',
            calibration_id='unverified',
            config=EvidencePipelineConfig(reference_limit=3, stride=2),
            model_runner=runner)
        self.assertGreater(result['model_inferences'], 0)
        self.assertEqual(len(result['model_output_chain_sha256']), 64)
        self.assertGreater(result['matched_keyframes'], 0)
        with SpatialEvidenceStore(db) as store:
            self.assertTrue(all(item.local_xyz_m is None
                                for item in store.query(session='testflight')))

    def test_non_onnx_backend_is_rejected(self):
        other = ModelArtifact('tiny-relu', '1.0.0', 'native', 'tiny.onnx',
            self.artifact.sha256, 64 * 1024, 1000.0, 3, 4)
        with self.assertRaises(ValueError):
            VerifiedONNXRunner(self.catalog, other, channels=1, width=2, height=2)


if __name__ == '__main__':
    unittest.main()
