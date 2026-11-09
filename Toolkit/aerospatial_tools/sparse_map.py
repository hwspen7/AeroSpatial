"""Bounded metric landmarks and traceable keyframe observations.

No landmark is assigned an absolute GPS coordinate without measured anchoring.
"""
from __future__ import annotations
from dataclasses import dataclass
import math
from collections import defaultdict
from itertools import product


@dataclass(frozen=True)
class Landmark:
    identifier: str
    xyz_m: tuple[float, float, float]
    standard_deviation_m: float
    source_frame: str
    clock_domain: int
    timestamp_ns: int


@dataclass(frozen=True)
class Keyframe:
    identifier: str
    timestamp_ns: int
    clock_domain: int
    calibration_id: str
    observed_landmarks: tuple[str, ...]


class SparseSpatialMap:
    def __init__(self, *, maximum_landmarks=10000, maximum_keyframes=1000, cell_size_m=5.0):
        if not 1 <= maximum_landmarks <= 100000 or not 1 <= maximum_keyframes <= 10000 or not math.isfinite(cell_size_m) or not .01 <= cell_size_m <= 10000:
            raise ValueError('invalid map budget')
        self.maximum_landmarks = maximum_landmarks
        self.maximum_keyframes = maximum_keyframes
        self.cell_size_m = float(cell_size_m)
        self._cells: dict[tuple[int, int, int], set[str]] = defaultdict(set)
        self.landmarks: dict[str, Landmark] = {}
        self.keyframes: dict[str, Keyframe] = {}

    def insert_landmark(self, point: Landmark) -> None:
        if (point.identifier in self.landmarks or len(self.landmarks) >= self.maximum_landmarks or
            not point.identifier or len(point.identifier) > 128 or not point.source_frame or
            len(point.xyz_m) != 3 or any(not math.isfinite(x) for x in point.xyz_m) or
            not math.isfinite(point.standard_deviation_m) or point.standard_deviation_m <= 0 or
            type(point.timestamp_ns) is not int or point.timestamp_ns < 0 or
            type(point.clock_domain) is not int or point.clock_domain <= 0):
            raise ValueError('invalid/duplicate landmark')
        self.landmarks[point.identifier] = point
        self._cells[self._cell(point.xyz_m)].add(point.identifier)

    def insert_keyframe(self, frame: Keyframe) -> None:
        if (not frame.identifier or frame.identifier in self.keyframes or
            len(self.keyframes) >= self.maximum_keyframes or not frame.calibration_id or
            type(frame.timestamp_ns) is not int or frame.timestamp_ns < 0 or
            type(frame.clock_domain) is not int or frame.clock_domain <= 0 or
            len(set(frame.observed_landmarks)) != len(frame.observed_landmarks) or
            any(identifier not in self.landmarks for identifier in frame.observed_landmarks)):
            raise ValueError('invalid/unknown keyframe evidence')
        if any(self.landmarks[x].clock_domain != frame.clock_domain for x in frame.observed_landmarks):
            raise ValueError('clock domains differ without explicit alignment')
        self.keyframes[frame.identifier] = frame

    def _cell(self, position):
        return tuple(math.floor(x/self.cell_size_m) for x in position)

    def nearby(self, xyz_m, radius_m: float, *, maximum_results=50) -> tuple[Landmark, ...]:
        if (len(xyz_m) != 3 or any(not math.isfinite(x) for x in xyz_m) or
            not math.isfinite(radius_m) or radius_m <= 0 or not 1 <= maximum_results <= 1000):
            raise ValueError('invalid spatial query')
        low = self._cell([x-radius_m for x in xyz_m])
        high = self._cell([x+radius_m for x in xyz_m])
        counts = [hi-lo+1 for lo,hi in zip(low,high)]
        # Never allocate a gigantic voxel neighborhood for an enormous search radius.
        if math.prod(counts) <= 100000:
            identifiers = (identifier for cell in product(*(range(a,b+1) for a,b in zip(low, high)))
                           for identifier in self._cells.get(cell, ()))
            candidates = (self.landmarks[identifier] for identifier in identifiers)
        else:
            candidates = self.landmarks.values()
        distance = sorted(((sum((x-y)**2 for x, y in zip(point.xyz_m, xyz_m)), point)
                           for point in candidates), key=lambda pair: (pair[0], pair[1].identifier))
        return tuple(item for square, item in distance if square <= radius_m * radius_m)[:maximum_results]
