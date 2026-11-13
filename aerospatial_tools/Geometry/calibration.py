"""Explicit, immutable, time-bounded optical calibration registry.

This is metadata validation, not a camera-calibration algorithm or GPS target locator.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite, sqrt
import re

_TOKEN = re.compile(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$')
_UINT = (1 << 64) - 1


@dataclass(frozen=True)
class OpticalCalibration:
    identifier: str
    device: str
    camera_frame: str
    revision: int
    valid_from_ns: int
    valid_until_ns: int
    fx: float
    fy: float
    cx: float
    cy: float
    width: int
    height: int
    camera_to_body_xyzw: tuple[float, float, float, float]
    translation_body_m: tuple[float, float, float]
    uncertainty_m: float

    def __post_init__(self) -> None:
        if any(not _TOKEN.fullmatch(getattr(self, key)) for key in
               ('identifier', 'device', 'camera_frame')):
            raise ValueError('invalid calibration identity')
        if (type(self.revision) is not int or self.revision < 1 or
            type(self.valid_from_ns) is not int or type(self.valid_until_ns) is not int or
            not 0 <= self.valid_from_ns < self.valid_until_ns <= _UINT):
            raise ValueError('invalid revision or validity interval')
        if (type(self.width) is not int or type(self.height) is not int or
            not 1 <= self.width <= 16384 or not 1 <= self.height <= 16384):
            raise ValueError('invalid frame dimensions')
        if any(not isfinite(value) for value in (self.fx, self.fy, self.cx, self.cy,
                                                 self.uncertainty_m)) or (
            self.fx <= 0 or self.fy <= 0 or self.uncertainty_m < 0 or
            not 0 <= self.cx <= self.width or not 0 <= self.cy <= self.height
        ):
            raise ValueError('invalid optical parameters')
        if (len(self.camera_to_body_xyzw) != 4 or
            len(self.translation_body_m) != 3 or
            any(not isfinite(value) for value in
                self.camera_to_body_xyzw + self.translation_body_m)):
            raise ValueError('invalid extrinsics')
        norm = sqrt(sum(value * value for value in self.camera_to_body_xyzw))
        if abs(norm - 1.0) > 1e-4:
            raise ValueError('rotation quaternion must be normalized')


class CalibrationRegistry:
    def __init__(self, capacity: int = 1024) -> None:
        if type(capacity) is not int or not 1 <= capacity <= 100_000:
            raise ValueError('invalid calibration capacity')
        self.capacity = capacity
        self._records: dict[tuple[str, str], list[OpticalCalibration]] = {}
        self._ids: set[str] = set()

    def add(self, item: OpticalCalibration) -> None:
        if item.identifier in self._ids or len(self._ids) >= self.capacity:
            raise ValueError('duplicate calibration or capacity exhausted')
        key = (item.device, item.camera_frame)
        bucket = self._records.setdefault(key, [])
        if any(item.valid_from_ns < current.valid_until_ns and
               current.valid_from_ns < item.valid_until_ns for current in bucket):
            raise ValueError('overlapping calibration validity intervals')
        bucket.append(item)
        bucket.sort(key=lambda current: current.valid_from_ns)
        self._ids.add(item.identifier)

    def resolve(self, device: str, frame: str, timestamp_ns: int) -> OpticalCalibration | None:
        if type(timestamp_ns) is not int or not 0 <= timestamp_ns <= _UINT:
            raise ValueError('invalid calibration query time')
        return next((item for item in self._records.get((device, frame), ())
                     if item.valid_from_ns <= timestamp_ns < item.valid_until_ns), None)
