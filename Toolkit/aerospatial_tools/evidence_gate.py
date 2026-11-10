"""Fail-closed release gate for *offline image-level* spatial evidence.

The gate validates persisted provenance, not metric geolocation accuracy.
"""
from __future__ import annotations
from math import isfinite

from .spatial_evidence import SpatialEvidenceStore


def evaluate_evidence(database, *, session: str, minimum_matches: int = 3,
                      maximum_uncertainty_ns: int = 100_000_000,
                      minimum_inlier_ratio: float = 0.45) -> dict:
    if (type(minimum_matches) is not int or not 1 <= minimum_matches <= 1000 or
        type(maximum_uncertainty_ns) is not int or not 1 <= maximum_uncertainty_ns <= 10**12 or
        not isfinite(minimum_inlier_ratio) or
        not 0 <= minimum_inlier_ratio <= 1):
        raise ValueError('invalid evidence acceptance thresholds')
    with SpatialEvidenceStore(database) as store:
        records = store.query(session=session, limit=1000)
    issues = []
    if len(records) < minimum_matches:
        issues.append('not_enough_verified_matches')
    if any(item.uncertainty_ns > maximum_uncertainty_ns for item in records):
        issues.append('clock_uncertainty_exceeded')
    if any(item.confidence < minimum_inlier_ratio for item in records):
        issues.append('visual_inlier_ratio_below_gate')
    if any(item.local_xyz_m is not None or item.metric_frame is not None for item in records):
        issues.append('unverified_metric_position')
    if len({(item.session, item.frame_index, item.trace_id) for item in records}) != len(records):
        issues.append('duplicate_observations')
    return {'passed': not issues, 'matched': len(records), 'issues': issues,
            'scope': 'image_level_evidence_only', 'required_matches': minimum_matches}
