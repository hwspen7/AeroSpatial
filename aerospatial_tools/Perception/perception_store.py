"""Opt-in indexed local store for camera-frame observations, not photographs."""

from __future__ import annotations

import sqlite3
from pathlib import Path
from .perception_models import FrameObservation, ImageBox


class PerceptionStore:
    def __init__(self, filename: Path):
        filename.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(filename)
        self.connection.execute("PRAGMA foreign_keys = ON")
        self.connection.execute("""CREATE TABLE IF NOT EXISTS perception_meta (
            key TEXT PRIMARY KEY, value TEXT NOT NULL)""")
        self.connection.execute("INSERT OR IGNORE INTO perception_meta VALUES ('version','1')")
        version = self.connection.execute(
            "SELECT value FROM perception_meta WHERE key='version'").fetchone()[0]
        if version != '1':
            self.connection.close()
            raise ValueError("unsupported perception store schema")
        self.connection.execute("""CREATE TABLE IF NOT EXISTS frame_observations (
            identifier TEXT PRIMARY KEY, session_id TEXT NOT NULL, frame_id TEXT NOT NULL,
            capture_uptime REAL NOT NULL, model_id TEXT NOT NULL, label TEXT NOT NULL,
            confidence REAL NOT NULL, left REAL NOT NULL, top REAL NOT NULL,
            width REAL NOT NULL, height REAL NOT NULL, coordinate_frame TEXT NOT NULL)""")
        self.connection.execute("CREATE INDEX IF NOT EXISTS frame_observations_session "
                                "ON frame_observations(session_id,capture_uptime)")
        self.connection.execute("CREATE INDEX IF NOT EXISTS frame_observations_label "
                                "ON frame_observations(label)")
        self.connection.commit()

    def __enter__(self) -> "PerceptionStore":
        return self

    def __exit__(self, *_: object) -> None:
        self.connection.close()

    def add(self, record: FrameObservation) -> bool:
        if not isinstance(record, FrameObservation):
            raise TypeError("expected a validated FrameObservation")
        # Revalidate reconstructed dataclasses as callers can instantiate them directly.
        FrameObservation.create(record.session_id, record.frame_id, record.capture_uptime,
                                record.model_id, record.label, record.confidence,
                                record.box, identifier=record.identifier)
        existing = self.connection.execute("SELECT * FROM frame_observations WHERE identifier=?",
                                           (record.identifier,)).fetchone()
        if existing is not None:
            if self._parse(existing) != record:
                raise ValueError("observation identifier collides with different content")
            return False
        with self.connection:
            cursor = self.connection.execute("""INSERT OR IGNORE INTO frame_observations
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
                (record.identifier, record.session_id, record.frame_id, record.capture_uptime,
                 record.model_id, record.label, record.confidence, record.box.left, record.box.top,
                 record.box.width, record.box.height, record.coordinate_frame))
        return cursor.rowcount == 1

    def by_session(self, session_id: str, limit: int = 100) -> list[FrameObservation]:
        if not 1 <= limit <= 10000:
            raise ValueError("query limit must be 1..10000")
        cursor = self.connection.execute("""SELECT * FROM frame_observations
            WHERE session_id=? ORDER BY capture_uptime,identifier LIMIT ?""", (session_id, limit))
        return [self._parse(row) for row in cursor]

    def by_label(self, label: str, limit: int = 100) -> list[FrameObservation]:
        if not 1 <= limit <= 10000:
            raise ValueError("query limit must be 1..10000")
        cursor = self.connection.execute("""SELECT * FROM frame_observations
            WHERE label=? ORDER BY capture_uptime,identifier LIMIT ?""", (label, limit))
        return [self._parse(row) for row in cursor]

    @staticmethod
    def _parse(row: tuple) -> FrameObservation:
        return FrameObservation(*row[:7], box=ImageBox(*row[7:11]), coordinate_frame=row[11])
