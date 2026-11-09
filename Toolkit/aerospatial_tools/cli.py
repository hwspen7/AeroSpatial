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
    export_cmd = commands.add_parser("journal-export", help="Verify and export CRC journal segments as JSONL")
    export_cmd.add_argument("source", type=Path)
    export_cmd.add_argument("destination", type=Path)
    video_cmd = commands.add_parser("video-probe", help="Decode offline video and inspect frame timing")
    video_cmd.add_argument("path", type=Path)
    video_cmd.add_argument("--max-frames", type=int, default=2000)
    match_cmd = commands.add_parser("vision-match", help="Estimate visual place overlap using ORB and RANSAC")
    match_cmd.add_argument("reference", type=Path)
    match_cmd.add_argument("query", type=Path)
    bench = commands.add_parser("benchmark", help="Measure offline streaming throughput")
    bench.add_argument("--count", type=int, default=100000)
    bench.add_argument("--iterations", type=int, default=5)
    args = parser.parse_args(argv)
    try:
        if args.command == "journal-export":
            from .journal_export import export_journal
            result = {"exported_records": export_journal(args.source, args.destination),
                      "destination": str(args.destination)}
            status = 0
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
