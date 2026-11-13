import hashlib
from pathlib import Path
import tempfile
import unittest

from aerospatial_tools.model_catalog import ModelArtifact, ModelCatalog
from aerospatial_tools.experiments import (ExperimentSpec, evaluate_experiment,
                                           file_digest, save_report, compare_reports)


class CatalogTests(unittest.TestCase):
    def test_digest_and_resource_negotiation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            binary = root/'model.bin'
            binary.write_bytes(b'weights:trusted-offline-fixture')
            model = ModelArtifact('object-detector', '1.2.0', 'native', binary.name,
                                  file_digest(binary), 2000, 12.0, 3, 4)
            catalog = ModelCatalog(root)
            catalog.add(model)
            self.assertEqual(catalog.choose('object-detector', available_backends={'native'},
                                            maximum_memory_bytes=4000, maximum_latency_ms=20), model)
            self.assertIsNone(catalog.choose('object-detector', available_backends={'coreml'},
                                             maximum_memory_bytes=4000, maximum_latency_ms=20))
            with self.assertRaises(ValueError): catalog.add(model)
            binary.write_bytes(b'altered')
            self.assertIsNone(catalog.choose('object-detector', available_backends={'native'},
                                             maximum_memory_bytes=4000, maximum_latency_ms=20))

    def test_symlink_and_path_traversal(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            outer = root/'outside.bin'
            outer.write_bytes(b'data')
            directory = root/'models'
            directory.mkdir()
            (directory/'link.bin').symlink_to(outer)
            model = ModelArtifact('object-detector', '1.0.0', 'native', 'link.bin',
                                  file_digest(outer), 1024, 3., 3, 4)
            with self.assertRaises(ValueError): ModelCatalog(directory).add(model)
            with self.assertRaises(ValueError):
                ModelArtifact('object-detector', '1.0.0', 'native', '../outside.bin',
                              file_digest(outer), 1024, 3., 3, 4)


class ExperimentTests(unittest.TestCase):
    def test_repeatability_and_regression(self):
        with tempfile.TemporaryDirectory() as temp:
            data = Path(temp)/'dataset.jsonl'
            data.write_text('0\n1\n2\n', encoding='utf-8')
            spec = ExperimentSpec(data, file_digest(data), 42, 'pose-estimator', '1.0.0')
            def evaluator(path, rng):
                return [abs(rng.gauss(0, .25)) for _ in range(100)]
            a = evaluate_experiment(spec, evaluator)
            b = evaluate_experiment(spec, evaluator)
            self.assertEqual(a, b)
            self.assertTrue(compare_reports(a, b)['passed'])
            worse = dict(b, rmsError=b['rmsError'] * 2)
            self.assertFalse(compare_reports(a, worse)['passed'])
            out = Path(temp)/'report.json'
            save_report(out, a)
            with self.assertRaises(FileExistsError): save_report(out, a)
            data.write_text('different')
            with self.assertRaises(ValueError): evaluate_experiment(spec, evaluator)

    def test_bad_metric_and_invalid_dataset(self):
        with tempfile.TemporaryDirectory() as temp:
            data = Path(temp)/'input'
            data.write_bytes(b'abc')
            spec = ExperimentSpec(data, file_digest(data), 3, 'algo', '1')
            for output in ([float('nan'), 1], [1, -1], [1]):
                with self.assertRaises(ValueError):
                    evaluate_experiment(spec, lambda _path, _rng: output)

if __name__ == '__main__':
    unittest.main()
