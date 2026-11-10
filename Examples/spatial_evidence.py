"""Minimal public API example: offline video place evidence, not navigation."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from aerospatial_tools.evidence_pipeline import index_video_evidence
from aerospatial_tools.evidence_gate import evaluate_evidence


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('observations', type=Path)
    parser.add_argument('database', type=Path)
    parser.add_argument('--session', required=True)
    parser.add_argument('--place', required=True)
    args = parser.parse_args()
    result = index_video_evidence(
        args.reference, args.observations, args.database,
        session=args.session, place_label=args.place, calibration_id='unverified')
    gate = evaluate_evidence(args.database, session=args.session)
    print(json.dumps({'ingestion': result, 'gate': gate}, indent=2, sort_keys=True))
    return 0 if gate['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
