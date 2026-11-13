"""Bounded, auditable offline video-to-place evidence integration.

Image-level place matches never become metric coordinates or GPS claims. Video
PTS is estimated by the decoder and its uncertainty is retained in storage.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from hashlib import sha256
from pathlib import Path
import re

from .spatial_evidence import SpatialEvidence, SpatialEvidenceStore
from .video_source import VideoFileSource
from .visual_memory import VisualPlaceMemory

_TOKEN = re.compile(r'^[A-Za-z0-9_-]{1,100}$')


@dataclass(frozen=True)
class EvidencePipelineConfig:
    reference_limit: int = 8
    frame_limit: int = 240
    stride: int = 5
    minimum_inliers: int = 12
    maximum_uncertainty_ns: int = 100_000_000
    maximum_pixels: int = 1920 * 1080

    def __post_init__(self) -> None:
        if (any(type(v) is not int for v in asdict(self).values()) or
            not 1 <= self.reference_limit <= 64 or
            not 1 <= self.frame_limit <= 100_000 or
            not 1 <= self.stride <= 10_000 or
            not 4 <= self.minimum_inliers <= 500 or
            not 1 <= self.maximum_uncertainty_ns <= 10**12 or
            not 1 <= self.maximum_pixels <= 4096 * 2160):
            raise ValueError('invalid bounded video evidence configuration')


def _digest(path: Path) -> str:
    result = sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            result.update(chunk)
    return result.hexdigest()


def index_video_evidence(reference: Path, observations: Path, database: Path, *,
                         session: str, place_label: str, calibration_id: str,
                         config: EvidencePipelineConfig | None = None,
                         model_runner=None) -> dict:
    """Index image evidence from two real video files, never inventing geolocation.

    A query frame is associated with a reference only after independent ORB
    matching and RANSAC inlier validation. Output includes source digests.
    """
    if any(type(token) is not str or not _TOKEN.fullmatch(token)
           for token in (session, place_label, calibration_id)):
        raise ValueError('invalid evidence provenance identifiers')
    cfg = config or EvidencePipelineConfig()
    reference = Path(reference)
    observations = Path(observations)
    database = Path(database)
    if database.resolve() in (reference.resolve(), observations.resolve()):
        raise ValueError('database cannot overwrite a source video')

    memory = VisualPlaceMemory(maximum_places=cfg.reference_limit,
                               minimum_inliers=cfg.minimum_inliers)
    reference_count = 0
    for frame in VideoFileSource(reference, maximum_frames=cfg.frame_limit,
                                 maximum_pixels=cfg.maximum_pixels).frames():
        if frame.index % cfg.stride or frame.uncertainty_ns > cfg.maximum_uncertainty_ns:
            continue
        try:
            memory.remember(f'{place_label}-{frame.index}', frame)
        except ValueError as exc:
            if str(exc) != 'insufficient visual texture':
                raise
            continue
        reference_count += 1
        if reference_count == cfg.reference_limit:
            break
    if not reference_count:
        raise ValueError('no usable visual reference keyframes')

    scanned = 0
    matched = 0
    model_inferences = 0
    model_digest = sha256()
    skipped_uncertain = 0
    with SpatialEvidenceStore(database) as store:
        for frame in VideoFileSource(observations, maximum_frames=cfg.frame_limit,
                                     maximum_pixels=cfg.maximum_pixels).frames():
            if frame.index % cfg.stride:
                continue
            scanned += 1
            if frame.uncertainty_ns > cfg.maximum_uncertainty_ns:
                skipped_uncertain += 1
                continue
            if model_runner is not None:
                _, summary = model_runner.infer_video_frame(frame.image)
                model_digest.update(str(frame.index).encode('ascii'))
                model_digest.update(summary.output_sha256.encode('ascii'))
                model_inferences += 1
            result = memory.recognize(frame)
            if result is None:
                continue
            # The inlier ratio is visual evidence strength, not a calibrated
            # probability that the location identity is correct.
            evidence = SpatialEvidence(
                identifier=f'{session}-{frame.index}', session=session,
                place_label=place_label, frame_index=frame.index,
                capture_ns=frame.presentation_ns,
                uncertainty_ns=frame.uncertainty_ns,
                trace_id=frame.index + 1, calibration_id=calibration_id,
                confidence=result.inlier_ratio,
                local_xyz_m=None, metric_frame=None)
            store.add(evidence)
            matched += 1
    return {
        'session': session, 'place': place_label,
        'reference_sha256': _digest(reference),
        'observations_sha256': _digest(observations),
        'reference_keyframes': reference_count,
        'observed_keyframes': scanned, 'matched_keyframes': matched,
        'skipped_clock_uncertainty': skipped_uncertain,
        'model_inferences': model_inferences,
        'model_output_chain_sha256': model_digest.hexdigest() if model_runner is not None else None,
        'location_model': 'image_only_unlocated',
        'timestamps': 'estimated_video_presentation',
        'database': str(database),
    }
