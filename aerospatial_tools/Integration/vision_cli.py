"""Public read-only commands for offline video and visual place evidence."""
from __future__ import annotations
from pathlib import Path

from .video_source import VideoFileSource
from .relocalization import VisualRelocalizer


def inspect_video(path: Path, *, maximum_frames: int = 2000) -> dict:
    first = last = None
    count = 0
    width = height = None
    for frame in VideoFileSource(path, maximum_frames=maximum_frames).frames():
        count += 1
        if first is None:
            first = frame.presentation_ns
        last = frame.presentation_ns
        width, height = frame.width, frame.height
    return {'frames': count, 'firstPresentationNs': first, 'lastPresentationNs': last,
            'width': width, 'height': height, 'clockSource': 'estimated_video_presentation'}


def match_images(reference: Path, query: Path, *, minimum_inliers: int = 12) -> dict:
    try:
        import cv2
    except ImportError as error:
        raise RuntimeError('OpenCV is required for image matching') from error
    base = cv2.imread(str(reference), cv2.IMREAD_COLOR)
    sample = cv2.imread(str(query), cv2.IMREAD_COLOR)
    if base is None or sample is None:
        raise ValueError('unable to decode images')
    index = VisualRelocalizer(minimum_inliers=minimum_inliers)
    index.register('reference', base)
    match = index.query(sample)
    return {'matched': match is not None, 'place': match.place_id if match else None,
            'inliers': match.inliers if match else 0,
            'inlierRatio': match.inlier_ratio if match else 0,
            'meaning': 'image-level hypothesis; not geographic localization'}
