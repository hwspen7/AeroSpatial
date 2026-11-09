"""AeroSpatial offline command-line tools. No SDK or aircraft connection."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from .performance import benchmark_stream
from .analysis import analyze
from .audit import audit
from .privacy import redact_session
from .faults import FAULTS, inject_fault
from .digest import create_digest, verify_digest
from .quality_gate import QualityThresholds, evaluate
from .simulation import generate
from .validation import validate
from .bus_events import InvalidBusEvent, read_bus_envelopes
from .bus_audit import BusAudit
from .algorithm import load_manifests
from .workload import WorkloadProfile, replay as workload_replay
from .trace_protocol import inspect_trace
from .events import InvalidSession
from .memory_storage import SpatialMemory
from .memory_models import Observation
from .memory_import import import_markers
from dataclasses import asdict


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="aerospatial")
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("validate", help="Validate JSONL integrity")
    check.add_argument("path", type=Path)
    report = commands.add_parser("report", help="Summarize offline session metrics")
    report.add_argument("path", type=Path)
    simulate = commands.add_parser("simulate", help="Generate a reproducible synthetic recording")
    simulate.add_argument("path", type=Path)
    simulate.add_argument("--seconds", type=float, default=30)
    simulate.add_argument("--seed", type=int, default=7)
    gate_cmd = commands.add_parser("gate", help="Apply reproducible JSON quality thresholds")
    gate_cmd.add_argument("path", type=Path)
    gate_cmd.add_argument("--profile", type=Path, required=True)
    audit_cmd = commands.add_parser("audit", help="Run semantic sensor/control quality rules")
    audit_cmd.add_argument("path", type=Path)
    privacy_cmd = commands.add_parser("sanitize", help="Create a separate, privacy-reduced log")
    privacy_cmd.add_argument("source", type=Path)
    privacy_cmd.add_argument("destination", type=Path)
    faults_cmd = commands.add_parser("inject-fault", help="Create deterministic damaged data for testing")
    faults_cmd.add_argument("source", type=Path)
    faults_cmd.add_argument("destination", type=Path)
    faults_cmd.add_argument("--fault", choices=FAULTS, required=True)
    digest_cmd = commands.add_parser("digest", help="Create or verify a SHA-256 corruption manifest")
    digest_cmd.add_argument("operation", choices=["create", "verify"])
    digest_cmd.add_argument("source", type=Path)
    digest_cmd.add_argument("manifest", type=Path)
    memory = commands.add_parser("memory", help="Local SQLite spatial observation metadata")
    memory.add_argument("operation", choices=["add", "list", "nearby", "import"])
    memory.add_argument("--db", type=Path, default=Path("aerospatial-memory.sqlite3"))
    memory.add_argument("--lat", type=float)
    memory.add_argument("--lon", type=float)
    memory.add_argument("--radius", type=float, default=500)
    memory.add_argument("--label", type=str)
    memory.add_argument("--note", type=str, default="")
    memory.add_argument("--session", type=Path)
    bus_cmd = commands.add_parser("bus-audit", help="Audit timestamped multimodal bus envelopes")
    bus_cmd.add_argument("path", type=Path)
    algorithm_cmd = commands.add_parser("algorithms", help="Validate and plan algorithm manifests")
    algorithm_cmd.add_argument("manifest", type=Path)
    trace_cmd = commands.add_parser("trace-audit", help="Audit causal algorithm spans")
    trace_cmd.add_argument("path", type=Path)
    workload_cmd = commands.add_parser("workload", help="Reproducible optional-compute overload experiment")
    workload_cmd.add_argument("--samples", type=int, default=3000)
    workload_cmd.add_argument("--seed", type=int, default=7)
    video_cmd = commands.add_parser("video-probe", help="Decode offline video and inspect frame timing")
    video_cmd.add_argument("path", type=Path)
    video_cmd.add_argument("--max-frames", type=int, default=2000)
    match_cmd = commands.add_parser("vision-match", help="Estimate visual place overlap using ORB and RANSAC")
    match_cmd.add_argument("reference", type=Path)
    match_cmd.add_argument("query", type=Path)
    spatial = commands.add_parser("spatial-demo", help="Run seeded metric geometry and optimization validation")
    spatial.add_argument("--seed", type=int, default=42)
    model_cmd = commands.add_parser("model-check", help="Verify offline model catalog and file hashes")
    model_cmd.add_argument("root", type=Path)
    model_cmd.add_argument("manifest", type=Path)
    experiment_cmd = commands.add_parser("experiment-errors", help="Reproducible error evaluation for JSONL")
    experiment_cmd.add_argument("dataset", type=Path)
    experiment_cmd.add_argument("sha256")
    experiment_cmd.add_argument("--seed", type=int, default=42)
    experiment_cmd.add_argument("--algorithm", default="offline-evaluator")
    experiment_cmd.add_argument("--revision", default="1.0.0")
    retention_cmd = commands.add_parser("retention-plan", help="Dry-run derived archive retention")
    retention_cmd.add_argument("directory", type=Path)
    retention_cmd.add_argument("--keep", type=int, default=2)
    retention_cmd.add_argument("--days", type=int, default=30)
    retention_cmd.add_argument("--now-ns", type=int, required=True)
    faults = commands.add_parser("replay-faults", help="Generate seeded synthetic arrival patterns")
    faults.add_argument("input", type=Path)
    faults.add_argument("--seed", type=int, default=42)
    bench = commands.add_parser("benchmark", help="Measure offline streaming throughput")
    bench.add_argument("--count", type=int, default=100000)
    bench.add_argument("--iterations", type=int, default=5)
    args = parser.parse_args(argv)
    try:
        if args.command == "model-check":
            from .model_catalog import ModelArtifact, ModelCatalog
            models = json.loads(args.manifest.read_text(encoding='utf-8'))
            if type(models) is not list or len(models) > 256:
                raise ValueError('invalid model manifest list')
            catalog = ModelCatalog(args.root)
            checked = []
            for entry in models:
                if type(entry) is not dict or set(entry) != {
                    'identifier', 'revision', 'backend', 'relativePath', 'sha256',
                    'memoryBytes', 'typicalLatencyMs', 'inputStream', 'outputStream'
                }:
                    raise ValueError('invalid model declaration fields')
                model = ModelArtifact(entry['identifier'], entry['revision'], entry['backend'],
                    entry['relativePath'], entry['sha256'], entry['memoryBytes'],
                    entry['typicalLatencyMs'], entry['inputStream'], entry['outputStream'])
                catalog.add(model)
                checked.append(model.identifier + '@' + model.revision)
            result, status = {'verified': checked, 'count': len(checked)}, 0
        elif args.command == 'experiment-errors':
            from .experiments import ExperimentSpec, evaluate_experiment
            spec = ExperimentSpec(args.dataset, args.sha256, args.seed,
                                  args.algorithm, args.revision)
            def errors(path, _rng):
                values = []
                with path.open('r', encoding='utf-8') as stream:
                    for line in stream:
                        values.append(json.loads(line)['error'])
                        if len(values) > 1_000_000:
                            raise ValueError('too many experiment error samples')
                return values
            result, status = evaluate_experiment(spec, errors), 0
        elif args.command == 'retention-plan':
            from .retention import RetentionPolicy, plan_retention
            plan = plan_retention(args.directory,
                 RetentionPolicy(args.keep, args.days * 86400), now_ns=args.now_ns)
            result, status = {'planDigest': plan.plan_digest,
                               'candidates': [item[0] for item in plan.candidates],
                               'mode': 'dry-run'}, 0
        elif args.command == 'replay-faults':
            from .device_replay import FaultProfile, replay_faults
            events = json.loads(args.input.read_text(encoding='utf-8'))
            result, status = replay_faults(events, FaultProfile(seed=args.seed)), 0
        elif args.command == "spatial-demo":
            from .spatial_demo import run
            result = run(seed=args.seed)
            status = 0 if result["status"] == "passed" else 1
        elif args.command == "video-probe":
            from .vision_cli import inspect_video
            result, status = inspect_video(args.path, maximum_frames=args.max_frames), 0
        elif args.command == "vision-match":
            from .vision_cli import match_images
            result, status = match_images(args.reference, args.query), 0
        elif args.command == "algorithms":
            result = {"executionOrder": [item.identifier for item in load_manifests(args.manifest).ordered()]}
            status = 0
        elif args.command == "trace-audit":
            result, status = inspect_trace(args.path), 0
        elif args.command == "workload":
            result, status = workload_replay(WorkloadProfile(seed=args.seed, samples=args.samples)), 0
        elif args.command == "bus-audit":
            bus_audit = BusAudit()
            for envelope in read_bus_envelopes(args.path):
                bus_audit.inspect(envelope)
            result, status = bus_audit.report(), 0
        elif args.command == "benchmark":
            result, status = benchmark_stream(args.count, args.iterations), 0
        elif args.command == "memory":
            with SpatialMemory(args.db) as store:
                if args.operation == "add":
                    if args.lat is None or args.lon is None or args.label is None:
                        parser.error("memory add requires --lat, --lon and --label")
                    result = asdict(observation) if store.add(observation := Observation.create(
                        args.lat, args.lon, args.label, args.note)) else {"status": "duplicate"}
                elif args.operation == "nearby":
                    if args.lat is None or args.lon is None:
                        parser.error("memory nearby requires --lat and --lon")
                    result = [{"distanceMeters": round(distance, 2), **asdict(observation)}
                              for distance, observation in store.nearby(args.lat, args.lon, args.radius)]
                elif args.operation == "import":
                    if args.session is None:
                        parser.error("memory import requires --session")
                    result = {"imported": import_markers(args.session, store)}
                else:
                    result = [asdict(item) for item in store.list_observations()]
            status = 0
        elif args.command == "gate":
            result = evaluate(args.path, QualityThresholds.from_file(args.profile))
            status = 0 if result["passed"] else 1
        elif args.command == "audit":
            outcome = audit(args.path)
            result = outcome.as_dict()
            status = 1 if outcome.errors else 0
        elif args.command == "sanitize":
            result = {"exported_records": redact_session(args.source, args.destination),
                      "destination": str(args.destination),
                      "warning": "Review custom numeric fields before publishing."}
            status = 0
        elif args.command == "inject-fault":
            inject_fault(args.source, args.destination, args.fault)
            result = {"fault": args.fault, "destination": str(args.destination)}
            status = 0
        elif args.command == "digest":
            if args.operation == "create":
                create_digest(args.source, args.manifest)
                result, status = {"created": str(args.manifest)}, 0
            else:
                matched = verify_digest(args.source, args.manifest)
                result, status = {"matched": matched}, 0 if matched else 1
        elif args.command == "simulate":
            result = {"generated_records": generate(args.path, args.seconds, args.seed),
                      "path": str(args.path)}
            status = 0
        elif args.command == "validate":
            result = validate(args.path).as_dict()
            status = 1 if result["issue_count"] else 0
        else:
            validation = validate(args.path)
            result = {"integrity": validation.as_dict(), "metrics": analyze(args.path).as_dict()}
            status = 1 if validation.issue_count else 0
    except (OSError, ValueError, RuntimeError, InvalidSession, InvalidBusEvent) as exc:
        print(json.dumps({"error": str(exc)}, indent=2))
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
