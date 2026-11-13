"""Accidental-corruption detection using a SHA-256 file digest.

This is NOT an authenticated signature: a malicious actor can replace both files.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def create_digest(source: Path, destination: Path) -> None:
    if source.resolve() == destination.resolve() or destination.exists():
        raise ValueError("digest output must be a new, separate file")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("x", encoding="utf-8") as output:
        output.write(json.dumps({"algorithm": "sha256", "sha256": file_sha256(source),
                                 "bytes": source.stat().st_size}, sort_keys=True) + "\n")


def verify_digest(source: Path, manifest: Path) -> bool:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("algorithm") != "sha256" or \
            type(data.get("bytes")) is not int or \
            not isinstance(data.get("sha256"), str):
        raise ValueError("invalid digest manifest")
    return data["bytes"] == source.stat().st_size and data["sha256"] == file_sha256(source)
