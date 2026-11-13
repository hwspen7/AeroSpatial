"""Import explicit camera markers as AIRCRAFT positions, not inferred target coordinates."""

from __future__ import annotations

from pathlib import Path
from uuid import uuid5, NAMESPACE_URL
from .events import read_events
from .memory_models import Observation
from .memory_storage import SpatialMemory


def import_markers(session: Path, database: SpatialMemory) -> int:
    inserted = 0
    for event in read_events(session):
        if event.kind != "spatial_marker" or event.session_id is None or event.sequence is None:
            continue
        lat = event.fields.get("latitude")
        lon = event.fields.get("longitude")
        if lat is None or lon is None:
            continue
        identifier = str(uuid5(NAMESPACE_URL, f"aerospatial:{event.session_id}:{event.sequence}"))
        observation = Observation.create(
            lat, lon, "Operator camera mark",
            "Recorded aircraft GPS position; not the geolocation of the camera target.",
            provenance=f"session:{event.session_id}", identifier=identifier)
        inserted += int(database.add(observation))
    return inserted
