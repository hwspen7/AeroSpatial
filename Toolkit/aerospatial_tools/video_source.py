"""Bounded offline video decoder that produces provenance-labelled observations.

Requires the optional OpenCV package. Container timestamps are presentation-time
estimates, not camera hardware capture timestamps. No DJI SDK connection here.
"""
from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path
import math


@dataclass(frozen=True)
class DecodedFrame:
    index: int
    presentation_ns: int
    estimated_clock: bool
    uncertainty_ns: int
    width: int
    height: int
    image: object


class VideoFileSource:
    def __init__(self, path: str | Path, *, maximum_pixels: int = 4096 * 2160,
                 maximum_frames: int = 50_000):
        if type(maximum_pixels) is not int or not 1 <= maximum_pixels <= 100_000_000:
            raise ValueError('invalid pixel budget')
        if type(maximum_frames) is not int or not 1 <= maximum_frames <= 1_000_000:
            raise ValueError('invalid frame limit')
        self.path = Path(path)
        if not self.path.is_file():
            raise FileNotFoundError(self.path)
        self.maximum_pixels = maximum_pixels
        self.maximum_frames = maximum_frames

    def frames(self):
        try:
            import cv2
        except ImportError as error:
            raise RuntimeError('OpenCV is required for offline video decoding') from error
        capture = cv2.VideoCapture(str(self.path))
        if not capture.isOpened():
            raise ValueError('cannot open video source')
        try:
            fps = capture.get(cv2.CAP_PROP_FPS)
            if not math.isfinite(fps) or fps <= 0 or fps > 1000:
                raise ValueError('video has no reliable frame rate')
            last_time = -1
            for index in range(self.maximum_frames):
                ok, image = capture.read()
                if not ok:
                    break
                height, width = image.shape[:2]
                if width <= 0 or height <= 0 or width * height > self.maximum_pixels:
                    raise ValueError('decoded frame exceeds pixel budget')
                presentation = capture.get(cv2.CAP_PROP_POS_MSEC)
                if not math.isfinite(presentation) or presentation < 0:
                    presentation = index * 1000.0 / fps
                timestamp = int(round(presentation * 1_000_000))
                # Some decoder backends report zero for every frame position.
                if timestamp <= last_time:
                    timestamp = max(last_time + 1, round(index * 1_000_000_000 / fps))
                last_time = timestamp
                yield DecodedFrame(index, timestamp, True, max(1, round(500_000_000 / fps)),
                                   width, height, image)
            else:
                if capture.grab():
                    raise OverflowError('video frame budget reached')
        finally:
            capture.release()
