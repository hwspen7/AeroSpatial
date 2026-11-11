from pathlib import Path
import tempfile
import unittest
from aerospatial_tools.model_catalog import ModelArtifact, ModelCatalog
from aerospatial_tools.experiments import file_digest
from aerospatial_tools.worker_supervisor import TrustedWorkerSupervisor
from aerospatial_tools.worker import IsolatedAlgorithmWorker, WorkerFailure, WorkerLimits


class SupervisorTests(unittest.TestCase):
    def test_trusted_worker_deploy_run_quarantine_and_reset(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            data = root/'weights.bin'
            data.write_bytes(b'trusted-reference')
            model = ModelArtifact('semantic-model', '1.0.0', 'native',
                                  data.name, file_digest(data), 1024, 5, 3, 4)
            catalog = ModelCatalog(root)
            catalog.add(model)
            worker = IsolatedAlgorithmWorker({'aerospatial_tools.worker_builtin:summarize',
                                              'aerospatial_tools.worker_builtin:fail'},
                                              WorkerLimits(timeout_seconds=1))
            runtime = TrustedWorkerSupervisor(catalog, worker, failure_limit=2)
            with self.assertRaises(WorkerFailure): runtime.execute({'values':[1]})
            with self.assertRaises(PermissionError):
                runtime.deploy(model, 'aerospatial_tools.worker_builtin:huge',
                               backends={'native'}, maximum_memory_bytes=2048,
                               maximum_latency_ms=10)
            runtime.deploy(model, 'aerospatial_tools.worker_builtin:summarize',
                           backends={'native'}, maximum_memory_bytes=2048,
                           maximum_latency_ms=10)
            self.assertEqual(runtime.execute({'values':[1,3]})['summarize.sum'], 4)
            self.assertEqual(runtime.status.successful, 1)
            data.write_bytes(b'tampered')
            for _ in range(2):
                with self.assertRaises(WorkerFailure): runtime.execute({})
            self.assertEqual(runtime.status.state, 'quarantined')
            with self.assertRaises(WorkerFailure): runtime.execute({})
            runtime.reset()
            self.assertEqual(runtime.status.state, 'stopped')
            with self.assertRaises(ValueError):
                runtime.deploy(model, 'aerospatial_tools.worker_builtin:summarize',
                               backends={'native'}, maximum_memory_bytes=2048,
                               maximum_latency_ms=10)

if __name__ == '__main__': unittest.main()
