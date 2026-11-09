"""Offline video-to-place evidence chain without making GPS claims.

Uses bounded descriptor storage. Every result includes the original frame evidence
and current observation's estimated presentation-time uncertainty.
"""
from __future__ import annotations
from dataclasses import dataclass
from .relocalization import VisualRelocalizer
from .video_source import DecodedFrame


@dataclass(frozen=True)
class PlaceEvidence:
    place_id: str
    reference_frame: int
    observed_frame: int
    observed_ns: int
    uncertainty_ns: int
    inliers: int
    inlier_ratio: float


class VisualPlaceMemory:
    def __init__(self, *, maximum_places: int = 32, minimum_inliers: int = 12):
        self.matcher = VisualRelocalizer(maximum_places=maximum_places,
                                         minimum_inliers=minimum_inliers)
        self.references: dict[str, int] = {}

    def remember(self, place_id: str, frame: DecodedFrame) -> None:
        self.matcher.register(place_id, frame.image)
        self.references[place_id] = frame.index

    def recognize(self, frame: DecodedFrame) -> PlaceEvidence | None:
        result = self.matcher.query(frame.image)
        if result is None:
            return None
        return PlaceEvidence(result.place_id, self.references[result.place_id],
                             frame.index, frame.presentation_ns, frame.uncertainty_ns,
                             result.inliers, result.inlier_ratio)
