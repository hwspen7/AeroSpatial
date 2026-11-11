import contextlib
from hashlib import sha256
import io
import json
from pathlib import Path
import tempfile
import unittest
from aerospatial_tools.cli import main


class P2CliTests(unittest.TestCase):
    def run_cli(self, arguments):
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            status = main(arguments)
        return status, json.loads(stream.getvalue())

    def test_model_catalog_cli_and_changed_binary(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            model = root/'detector.bin'
            model.write_bytes(b'stable-test-weights')
            declaration = {'identifier': 'scene-detector', 'revision': '1.0.0',
                           'backend': 'native', 'relativePath': 'detector.bin',
                           'sha256': sha256(model.read_bytes()).hexdigest(),
                           'memoryBytes': 1024, 'typicalLatencyMs': 5.,
                           'inputStream': 3, 'outputStream': 4}
            manifest = root/'models.json'
            manifest.write_text(json.dumps([declaration]))
            status, report = self.run_cli(['model-check', str(root), str(manifest)])
            self.assertEqual(status, 0)
            self.assertEqual(report['count'], 1)
            model.write_bytes(b'modified')
            status, report = self.run_cli(['model-check', str(root), str(manifest)])
            self.assertEqual(status, 2)
            self.assertIn('digest', report['error'])

    def test_experiment_and_faults_cli(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            dataset = root/'errors.jsonl'
            dataset.write_text(''.join(json.dumps({'error': v})+'\n' for v in (0., 1., 2., 3.)))
            digest = sha256(dataset.read_bytes()).hexdigest()
            status, report = self.run_cli(['experiment-errors', str(dataset), digest])
            self.assertEqual(status, 0)
            self.assertEqual(report['sampleCount'], 4)
            status, report = self.run_cli(['experiment-errors', str(dataset), '0'*64])
            self.assertEqual(status, 2)
            cases = root/'events.json'
            cases.write_text(json.dumps([{'stream':3,'timestampNs':i*1000} for i in range(10)]))
            status, result = self.run_cli(['replay-faults', str(cases), '--seed', '42'])
            self.assertEqual(status, 0)
            self.assertEqual(result['sourceEvents'], 10)

if __name__ == '__main__': unittest.main()
