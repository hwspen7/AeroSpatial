"""Auditable, bounded spatial observation evidence, not geographic target claims.

Only frame metadata and calibrated-local location hypotheses are persisted.
Pixels, raw video and wearable motion are not stored by this module.
"""
from __future__ import annotations
from dataclasses import dataclass
from math import isfinite
import re
import sqlite3
from pathlib import Path

_ID = re.compile(r'^[A-Za-z0-9_-]{1,100}$')


@dataclass(frozen=True)
class SpatialEvidence:
    identifier: str
    session: str
    place_label: str
    frame_index: int
    capture_ns: int
    uncertainty_ns: int
    trace_id: int
    calibration_id: str
    confidence: float
    local_xyz_m: tuple[float, float, float] | None = None
    metric_frame: str | None = None

    def __post_init__(self) -> None:
        if any(type(x) is not str or not _ID.fullmatch(x) for x in
               (self.identifier, self.session, self.place_label, self.calibration_id)):
            raise ValueError('invalid spatial evidence identity')
        if (type(self.frame_index) is not int or self.frame_index < 0 or
            any(type(value) is not int or value < 0 or value > (1 << 63)-1 for value in
                (self.capture_ns, self.uncertainty_ns, self.trace_id)) or
            not isfinite(self.confidence) or not 0 <= self.confidence <= 1):
            raise ValueError('invalid observation metadata')
        if self.local_xyz_m is not None:
            if (self.metric_frame is None or not _ID.fullmatch(self.metric_frame) or
                len(self.local_xyz_m) != 3 or any(not isfinite(v) for v in self.local_xyz_m)):
                raise ValueError('metric evidence requires a frame and finite coordinates')
        elif self.metric_frame is not None:
            raise ValueError('frame cannot imply unknown coordinates')


class SpatialEvidenceStore:
    def __init__(self, database: Path):
        self.connection = sqlite3.connect(str(database))
        self.connection.execute('PRAGMA foreign_keys=ON')
        self.connection.execute('PRAGMA journal_mode=WAL')
        self.connection.execute('''CREATE TABLE IF NOT EXISTS evidence (
          id TEXT PRIMARY KEY, session TEXT NOT NULL, place_label TEXT NOT NULL,
          frame_index INTEGER NOT NULL, capture_ns INTEGER NOT NULL,
          uncertainty_ns INTEGER NOT NULL, trace_id INTEGER NOT NULL,
          calibration_id TEXT NOT NULL, confidence REAL NOT NULL,
          x REAL, y REAL, z REAL, metric_frame TEXT,
          UNIQUE(session, frame_index, trace_id))''')
        self.connection.execute('''CREATE INDEX IF NOT EXISTS evidence_time
                                ON evidence(session, capture_ns)''')
        self.connection.execute('''CREATE INDEX IF NOT EXISTS evidence_place
                                ON evidence(place_label, capture_ns)''')
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()

    def __enter__(self): return self
    def __exit__(self, *_): self.close()

    def add(self, evidence: SpatialEvidence) -> None:
        xyz = evidence.local_xyz_m or (None, None, None)
        with self.connection:
            self.connection.execute('''INSERT INTO evidence VALUES
             (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
             (evidence.identifier, evidence.session, evidence.place_label,
              evidence.frame_index, evidence.capture_ns, evidence.uncertainty_ns,
              evidence.trace_id, evidence.calibration_id, evidence.confidence,
              *xyz, evidence.metric_frame))

    def query(self, *, session: str | None = None, place_label: str | None = None,
              before_ns: int | None = None, maximum_uncertainty_ns: int | None = None,
              minimum_confidence: float = 0, limit: int = 100) -> list[SpatialEvidence]:
        if (not 1 <= limit <= 1000 or not isfinite(minimum_confidence) or
            not 0 <= minimum_confidence <= 1 or
            any(v is not None and (type(v) is not int or v < 0 or v > (1 << 63)-1)
                for v in (before_ns, maximum_uncertainty_ns))):
            raise ValueError('invalid spatial query')
        clauses = ['confidence >= ?']
        parameters: list = [minimum_confidence]
        for name, field in [('session', session), ('place_label', place_label)]:
            if field is not None:
                if not _ID.fullmatch(field): raise ValueError('invalid identity')
                clauses.append(name+' = ?')
                parameters.append(field)
        if before_ns is not None:
            clauses.append('capture_ns <= ?')
            parameters.append(before_ns)
        if maximum_uncertainty_ns is not None:
            clauses.append('uncertainty_ns <= ?')
            parameters.append(maximum_uncertainty_ns)
        statement = 'SELECT * FROM evidence WHERE ' + ' AND '.join(clauses) + \
                    ' ORDER BY capture_ns, id LIMIT ?'
        rows = self.connection.execute(statement, [*parameters, limit]).fetchall()
        return [SpatialEvidence(id, session, place, frame, capture, uncertainty,
                                trace, calibration, confidence,
                                None if x is None else (x, y, z), metric)
                for (id, session, place, frame, capture, uncertainty,
                     trace, calibration, confidence, x, y, z, metric) in rows]
