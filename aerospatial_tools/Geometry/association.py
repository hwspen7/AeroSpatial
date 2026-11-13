"""Associate detections with camera frames without claiming geographic position."""
from __future__ import annotations
from dataclasses import dataclass
from bisect import bisect_left
import math

from .perception_models import FrameObservation


@dataclass(frozen=True)
class FrameEvidence:
    frame_id: str
    session_id: str
    aligned_uptime: float
    uncertainty_seconds: float
    trace_id: int
    quality_valid: bool = True

    def __post_init__(self):
        if not self.frame_id or not self.session_id or self.trace_id < 0 or (
            not math.isfinite(self.aligned_uptime) or self.aligned_uptime < 0 or
            not math.isfinite(self.uncertainty_seconds) or self.uncertainty_seconds < 0
        ):
            raise ValueError('invalid frame evidence')


@dataclass(frozen=True)
class Association:
    observation_id: str
    frame_id: str
    trace_id: int
    skew_seconds: float
    uncertainty_seconds: float


def associate(frames: list[FrameEvidence], observations: list[FrameObservation],
              *, maximum_skew: float = 0.05) -> list[Association]:
    if not math.isfinite(maximum_skew) or maximum_skew < 0:
        raise ValueError('invalid skew allowance')
    by_frame: dict[tuple[str, str], list[FrameEvidence]] = {}
    for frame in frames:
        if frame.quality_valid:
            by_frame.setdefault((frame.session_id, frame.frame_id), []).append(frame)
    for group in by_frame.values():
        group.sort(key=lambda frame: frame.aligned_uptime)
    result = []
    for observation in observations:
        group = by_frame.get((observation.session_id, observation.frame_id), [])
        if not group:
            continue
        times = [frame.aligned_uptime for frame in group]
        position = bisect_left(times, observation.capture_uptime)
        nearest = min(group[max(0, position - 1):min(len(group), position + 1)],
                      key=lambda frame: abs(frame.aligned_uptime - observation.capture_uptime))
        skew = abs(nearest.aligned_uptime - observation.capture_uptime)
        if skew + nearest.uncertainty_seconds <= maximum_skew:
            result.append(Association(observation.identifier, nearest.frame_id,
                                      nearest.trace_id, skew, nearest.uncertainty_seconds))
    return result
