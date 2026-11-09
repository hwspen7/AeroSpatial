"""Typed future-perception evidence. A detection never implies target geolocation."""

from __future__ import annotations

import math
from dataclasses import dataclass
from uuid import uuid4


@dataclass(frozen=True)
class ImageBox:
    left: float
    top: float
    width: float
    height: float

    def __post_init__(self) -> None:
        values = (self.left, self.top, self.width, self.height)
        if any(isinstance(x, bool) or not isinstance(x, (int, float)) or
               not math.isfinite(x) for x in values):
            raise ValueError("image box values must be finite numbers")
        if not (0 <= self.left < 1 and 0 <= self.top < 1 and
                0 < self.width <= 1 and 0 < self.height <= 1 and
                self.left + self.width <= 1 + 1e-9 and
                self.top + self.height <= 1 + 1e-9):
            raise ValueError("image box must be normalized into [0,1]")


@dataclass(frozen=True)
class FrameObservation:
    identifier: str
    session_id: str
    frame_id: str
    capture_uptime: float
    model_id: str
    label: str
    confidence: float
    box: ImageBox
    coordinate_frame: str = "camera_image"

    def __post_init__(self) -> None:
        if self.coordinate_frame != "camera_image":
            raise ValueError("a normalized image detection must use the camera_image frame")

    @classmethod
    def create(cls, session_id: str, frame_id: str, capture_uptime: float,
               model_id: str, label: str, confidence: float, box: ImageBox,
               identifier: str | None = None) -> "FrameObservation":
        for name, value in (("session_id", session_id), ("frame_id", frame_id),
                            ("model_id", model_id), ("label", label)):
            if not isinstance(value, str) or not value.strip() or len(value) > 128:
                raise ValueError(f"{name} must be nonempty text <= 128 chars")
        if (not isinstance(box, ImageBox) or not isinstance(capture_uptime, (float, int)) or
                isinstance(capture_uptime, bool) or not math.isfinite(capture_uptime) or
                capture_uptime < 0 or not isinstance(confidence, (float, int)) or
                isinstance(confidence, bool) or not math.isfinite(confidence) or
                not 0 <= confidence <= 1):
            raise ValueError("invalid frame timing, bounding box or confidence")
        if identifier is not None and (not isinstance(identifier, str) or
                                       not 1 <= len(identifier) <= 128):
            raise ValueError("invalid observation ID")
        return cls(identifier or str(uuid4()), session_id, frame_id,
                   float(capture_uptime), model_id, label, float(confidence), box)
