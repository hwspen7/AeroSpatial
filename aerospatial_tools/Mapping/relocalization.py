"""Visual place retrieval with ORB descriptors and RANSAC geometric validation.

Returns an image-level place hypothesis, never a geographic fix. The algorithm
needs texture, sufficient overlap and independent calibration to support mapping.
"""
from __future__ import annotations
from dataclasses import dataclass


@dataclass(frozen=True)
class VisualMatch:
    place_id: str
    tentative_matches: int
    inliers: int
    inlier_ratio: float


class VisualRelocalizer:
    def __init__(self, *, maximum_places: int = 32, features_per_image: int = 600,
                 minimum_inliers: int = 12):
        if not 1 <= maximum_places <= 10000 or not 64 <= features_per_image <= 4096 or (
            not 4 <= minimum_inliers <= features_per_image
        ):
            raise ValueError('invalid visual index capacity or RANSAC threshold')
        try:
            import cv2
        except ImportError as error:
            raise RuntimeError('OpenCV required for visual relocalization') from error
        self.cv2 = cv2
        self.detector = cv2.ORB_create(nfeatures=features_per_image)
        self.maximum_places = maximum_places
        self.minimum_inliers = minimum_inliers
        self._entries: dict[str, tuple[object, object]] = {}

    def _extract(self, image):
        import numpy as np
        if not isinstance(image, np.ndarray) or image.ndim not in (2, 3) or (
            image.ndim == 3 and image.shape[2] not in (1, 3, 4)
        ) or image.dtype != np.uint8 or image.shape[0] * image.shape[1] > 8192 * 8192:
            raise ValueError('invalid image')
        return self.detector.detectAndCompute(image, None)

    def register(self, place_id: str, image) -> None:
        if type(place_id) is not str or not place_id or len(place_id) > 128 or (
            place_id in self._entries or len(self._entries) >= self.maximum_places
        ):
            raise ValueError('duplicate identifier or full index')
        points, descriptors = self._extract(image)
        if descriptors is None or len(points) < self.minimum_inliers:
            raise ValueError('insufficient visual texture')
        coordinates = [(point.pt[0], point.pt[1]) for point in points]
        self._entries[place_id] = (coordinates, descriptors.copy())

    def query(self, image) -> VisualMatch | None:
        import numpy as np
        points, descriptors = self._extract(image)
        if descriptors is None or len(points) < self.minimum_inliers:
            return None
        query_points = np.float32([point.pt for point in points])
        matcher = self.cv2.BFMatcher(self.cv2.NORM_HAMMING, crossCheck=False)
        best: VisualMatch | None = None
        for place_id, (stored_points, stored_desc) in self._entries.items():
            # Ratio-test reduces ambiguous descriptor associations.
            pairs = matcher.knnMatch(stored_desc, descriptors, k=2)
            matches = [a for pair in pairs if len(pair) == 2
                       for a, b in [pair] if a.distance < 0.75 * b.distance]
            if len(matches) < self.minimum_inliers:
                continue
            source = np.float32([stored_points[m.queryIdx] for m in matches])
            destination = np.float32([query_points[m.trainIdx] for m in matches])
            # RANSAC verifies that matches agree with one shared 2D transform.
            _, mask = self.cv2.estimateAffinePartial2D(source, destination,
                                                       method=self.cv2.RANSAC,
                                                       ransacReprojThreshold=3.0,
                                                       maxIters=1000, confidence=0.99)
            if mask is None:
                continue
            inliers = int(mask.sum())
            if inliers < self.minimum_inliers or inliers / len(matches) < 0.45:
                continue
            match = VisualMatch(place_id, len(matches), inliers, inliers / len(matches))
            if best is None or (match.inliers, match.inlier_ratio) > (best.inliers, best.inlier_ratio):
                best = match
        return best
