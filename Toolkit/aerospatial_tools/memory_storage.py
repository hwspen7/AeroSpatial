"""SQLite storage for observed positions. Aircraft positions are not object locations."""

from __future__ import annotations

import sqlite3
from dataclasses import asdict
from pathlib import Path
from typing import Iterator
from .memory_models import Observation
from .memory_query import great_circle_meters


class SpatialMemory:
    def __init__(self, filename: Path):
        self.filename = filename
        filename.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(filename)
        self.connection.execute("PRAGMA foreign_keys = ON")
        self.connection.execute("CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        self.connection.execute("INSERT OR IGNORE INTO schema_meta VALUES ('version', '1')")
        version = self.connection.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
        if version != '1':
            self.connection.close()
            raise ValueError(f"unsupported spatial memory schema: {version}")
        self.connection.execute("""CREATE TABLE IF NOT EXISTS observations (
            identifier TEXT PRIMARY KEY, latitude REAL NOT NULL, longitude REAL NOT NULL,
            label TEXT NOT NULL, note TEXT NOT NULL, timestamp_utc TEXT NOT NULL,
            provenance TEXT NOT NULL)""")
        self.connection.execute("CREATE INDEX IF NOT EXISTS observations_location ON observations(latitude, longitude)")
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()

    def __enter__(self) -> "SpatialMemory":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def add(self, observation: Observation) -> bool:
        with self.connection:
            cursor = self.connection.execute("""INSERT OR IGNORE INTO observations
                (identifier, latitude, longitude, label, note, timestamp_utc, provenance)
                VALUES (:identifier,:latitude,:longitude,:label,:note,:timestamp_utc,:provenance)""",
                asdict(observation))
        return cursor.rowcount == 1

    def list_observations(self, limit: int = 200) -> list[Observation]:
        if not 1 <= limit <= 10_000:
            raise ValueError("limit must be 1..10000")
        rows = self.connection.execute("SELECT * FROM observations ORDER BY timestamp_utc DESC LIMIT ?",
                                       (limit,)).fetchall()
        return [Observation(*row) for row in rows]

    def nearby(self, latitude: float, longitude: float, radius_meters: float,
               limit: int = 50) -> list[tuple[float, Observation]]:
        # Validation and bounded query prevents surprising full-range operations.
        Observation.create(latitude, longitude, "query")
        if not 0 < radius_meters <= 100_000 or not 1 <= limit <= 1000:
            raise ValueError("radius must be <=100 km and limit <=1000")
        latitude_span = radius_meters / 111_000 + .01
        rows = self.connection.execute("SELECT * FROM observations WHERE latitude BETWEEN ? AND ?",
                                       (latitude - latitude_span, latitude + latitude_span)).fetchall()
        candidates = [(great_circle_meters(latitude, longitude, row[1], row[2]), Observation(*row))
                      for row in rows]
        candidates = [(distance, entry) for distance, entry in candidates if distance <= radius_meters]
        return sorted(candidates, key=lambda item: item[0])[:limit]
