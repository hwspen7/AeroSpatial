#!/usr/bin/env python3
"""Fail-closed inspection of manually collected physical bench evidence.

No flags or fixture can prove the measurements came from real hardware.
The program checks structural completeness, constraints, and numerical bounds.
It deliberately cannot grant flight or gimbal permissions.
"""

import argparse
import json
import math
import sys
from pathlib import Path


REQUIRED_STRING = ("device_model", "ios_version", "dji_sdk_version", "aircraft_firmware")
REQUIRED_TRUE = ("physical_device", "propellers_removed", "manual_controller_ready",
                 "sdk_linked", "sdk_registered", "verified_mavic_air_2",
                 "manual_stop_observed", "disconnect_stopped_video")
COUNTERS = ("encoded_callbacks", "complete_access_units", "decoded_pixel_buffers")


def audit(record: object) -> list[str]:
    if not isinstance(record, dict):
        return ["Evidence must be a JSON object"]
    problems: list[str] = []
    for key in REQUIRED_STRING:
        if not isinstance(record.get(key), str) or not record[key].strip():
            problems.append(f"Missing {key}")
    if record.get("device_model") != "DJI Mavic Air 2":
        problems.append("Aircraft must be explicitly identified as DJI Mavic Air 2")
    if record.get("dji_sdk_version") != "4.16.2":
        problems.append("SDK version must match the pinned 4.16.2 build")
    for key in REQUIRED_TRUE:
        if record.get(key) is not True:
            problems.append(f"Gate not observed: {key}")
    for key in COUNTERS:
        value = record.get(key)
        if type(value) is not int or value < 30:
            problems.append(f"Insufficient real observations: {key} must be >= 30")
    if all(type(record.get(k)) is int for k in COUNTERS):
        if record["decoded_pixel_buffers"] > record["complete_access_units"]:
            problems.append("Decoded pixel buffers exceed submitted access units")
    for key in ("queue_p95_ms", "decode_p95_ms", "decode_p99_ms", "peak_rss_mb"):
        value = record.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            problems.append(f"Missing or non-finite measured value: {key}")
    if isinstance(record.get("decode_p95_ms"), (int, float)) and isinstance(record.get("decode_p99_ms"), (int, float)):
        if record["decode_p99_ms"] < record["decode_p95_ms"]:
            problems.append("p99 cannot be less than p95")
    for key in ("evidence_log_sha256", "operator_review"):
        if not isinstance(record.get(key), str) or not record[key].strip():
            problems.append(f"Missing provenance: {key}")
    digest = record.get("evidence_log_sha256")
    if isinstance(digest, str) and (len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest)):
        problems.append("Evidence log SHA-256 must be lowercase hex")
    if record.get("camera_capture_clock_verified") is True:
        skew = record.get("measured_capture_clock_uncertainty_ms")
        if isinstance(skew, bool) or not isinstance(skew, (int, float)) or not math.isfinite(skew) or skew < 0:
            problems.append("Capture clock verification requires measured uncertainty")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate collected Mavic Air 2 bench evidence")
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    try:
        record = json.loads(args.evidence.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"BLOCKED: unable to read evidence: {error}")
        return 2
    problems = audit(record)
    if problems:
        print("BLOCKED: physical preflight evidence is incomplete")
        for problem in problems:
            print(" -", problem)
        return 2
    print("EVIDENCE CHECK PASSED: required bench observations were supplied.")
    print("This is not proof of measurement authenticity, flightworthiness, or calibrated SLAM.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
