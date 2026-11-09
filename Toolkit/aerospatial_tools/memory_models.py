"""Privacy-preserving, explicitly user-authored spatial observation metadata."""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timezone
from uuid import uuid4


@dataclass(frozen=True)
class Observation:
    identifier: str
    latitude: float
    longitude: float
    label: str
    note: str
    timestamp_utc: str
    provenance: str

    @classmethod
    def create(cls, latitude: float, longitude: float, label: str,
               note: str = "", provenance: str = "manual", identifier: str | None = None) -> "Observation":
        if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v)
               for v in (latitude, longitude)) or abs(latitude) > 90 or abs(longitude) > 180:
            raise ValueError("invalid latitude/longitude")
        if not isinstance(label, str) or not label.strip() or len(label) > 160:
            raise ValueError("label length must be 1..160")
        if not isinstance(note, str) or len(note) > 4000:
            raise ValueError("note length must be 0..4000")
        if not isinstance(provenance, str) or len(provenance) > 128:
            raise ValueError("invalid provenance")
        return cls(identifier or str(uuid4()), float(latitude), float(longitude), label,
                   note, datetime.now(timezone.utc).isoformat(), provenance)
