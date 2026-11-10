# P3 — integration and delivery contracts

P3 was not a previously defined phase in the AeroSpatial roadmap. This
engineering release defines P3 narrowly as an **offline integration and
mobile-observability milestone**. It does not assert completion of unresolved
physical P0–P2 hardware acceptance gates.

## 1. Verified local inference

`Toolkit/aerospatial_tools/onnx_inference.py` loads a SHA-256 verified,
trusted **ONNX** artifact with OpenCV DNN on the CPU. Its input image layout,
normalization, maximum output size, observed latency and output hash are
explicit. A real `Relu` ONNX graph is executed in the automated test. OpenCV
model loading is not an OS sandbox, post-return deadline detection is not
hard real-time, SHA-256 is not a signature, and neural outputs are not
implicitly geolocated or routed to drone control.

`App/CoreMLModelRunner.swift` provides an optional iOS-only **Core ML** loader
for a verified `.mlmodel` file. It compiles and loads the model, then calls
Core ML prediction on caller-supplied `MLFeatureProvider` inputs. iOS builds
must exercise this source in Xcode, and an actual compatible `.mlmodel`, target
iPhone, compute-unit profile and latency measurement are required for model
acceptance. This adapter is not wired to the aircraft.

## 2. Video-to-spatial-evidence pipeline

The `video-evidence` CLI accepts a reference video, observation video,
local SQLite database and explicit session/place/calibration identifiers.
OpenCV decodes actual file frames. ORB descriptors plus RANSAC independently
validate place correspondence. Each accepted observation is persisted using
`SpatialEvidenceStore` with source session, frame index, estimated frame time,
time uncertainty, frame trace ID and non-probabilistic inlier ratio. SHA-256
source video digests are returned for reproducibility.

A caller can also pass a verified `VerifiedONNXRunner` to `index_video_evidence`
so sampled decoded video frames execute an actual model forward pass in the
same observation run. The report includes the number of model evaluations
and a deterministic chain digest of their output hashes. The generic ONNX
output does **not** automatically become a location or detection.

There is **no** inferred GPS position, no local 3D coordinate, no metric SLAM
claim and no live DJI video callback in this workflow. Images are decoded in
memory; the evidence store holds metadata rather than video pixels. The
quality gate rejects missing evidence, insufficient matches, uncertainty
violations, low inlier ratios and unverified metric coordinates.

```sh
python -m pip install -e './Toolkit[vision]'
PYTHONPATH=Toolkit python -m aerospatial_tools video-evidence \
  reference.avi observations.avi observations.sqlite3 \
  --session experiment01 --place testsite --calibration unverified
PYTHONPATH=Toolkit python -m aerospatial_tools evidence-gate \
  observations.sqlite3 --session experiment01 --minimum-matches 3
PYTHONPATH=Toolkit python Examples/spatial_evidence.py --help
```

## 3. Privacy-safe sharing and diagnostics

`SessionPrivacyExport` rejects malformed/truncated source logs, preserves
sequential ordering and writes only a new shareable file. It allows only
known non-location numeric fields, replacing absolute timestamps and
session IDs, and removing notes, coordinates and unknown fields. No raw
session file is passed to `ShareLink`. The user explicitly prepares and
reviews the privacy-reduced copy before sharing. Event identifiers may still
carry information and should be reviewed for sensitive custom values.

The SwiftUI diagnostics surface native head/telemetry publication results,
H.264 ingest/drop counters, control-loop latency and the platform thermal
level. These are observed counters, not measured GPU utilization or a proof
of end-to-end motion latency.

## 4. External developer integration

`ROSPosePublisher` can publish a verified `PoseStamped` through a caller-owned
ROS 2 node with `geometry_msgs`. It rejects non-calibrated poses and missing
ROS-domain timestamps. Automated tests use a fake ROS node; no real ROS 2
installation, DDS networking or external-client interoperability is claimed.
The publisher exposes observation data only, never aircraft commands.

## P3 release quality gates

1. Complete native C++, Swift, Python regression and sanitizer checks.
2. Verify real ONNX CPU inference against known numeric results.
3. Decode real generated video files and write evidence to SQLite.
4. Reject blank-scene matches, invalid paths, missing evidence and invalid
   provenance.
5. Test privacy-safe export and malformed/oversized session rejection.
6. Build iOS simulator in Xcode, including the optional Core ML source.
7. Verify that no P3 module changes the bench-only command authorization.

Hardware acceptance remains separate and must contain measured source clock
uncertainty, supported controller/firmware, signed iPhone build, live DJI
video, target hardware inference performance and propeller-off stop tests.
