# P2 developer platform and adaptive spatial interfaces

P2 extends the portable AeroSpatial foundation without merging unverified
hardware inputs into aircraft control. C++ handles high-rate numerical decisions,
Swift owns device-facing typed contracts, and Python owns independent research,
local artifact governance, repeatable experiments, and integration scaffolding.

## Native, device-neutral algorithms

- `Kernel/adaptive.cpp` and `include/aerospatial_adaptive.h` implement bounded,
  deterministic admission-quality decisions for **optional** video/perception
  only. Quality 0..3 is a recommendation; an application must explicitly apply
  it to its decoder or inference scheduler. Safety and actuator paths do not use it.
- A short-horizon head-look preview uses wrapped angular differentiation,
  exponential rate smoothing, rate limits and stale/outlier rejection. It is
  **not** gimbal motion planning, command authorization or eye tracking.
- Native ABI structs are caller-owned, contain no heap pointers, and have
  cross-platform C linkage; tests include 30Hz recovery, hysteresis,
  wraparound, malformed inputs and non-mutating failed updates.

## Portable Swift contracts

- `Core/AdaptivePerception.swift` exposes the native governor and head-intent
  visual preview, without connecting to flight commands.
- `Core/ModelDeployment.swift` validates constrained model manifests and can
  choose a declared compatible backend within memory/latency budgets. It never
  loads model weights or treats a digest as publisher authentication.
- `Core/TimedFrameGraph.swift` records revisions of child-to-parent transforms
  and refuses ambiguous, stale, wrong-domain or uncertainty-spanning lookups.
  It does **not** derive or certify physical extrinsic calibration.

## Python developer environment

- `model_catalog.py`: exact SHA-256 of local artifacts, path/symlink protection,
  resource-constrained backend planning. Selection does not execute a model.
- `worker_supervisor.py`: explicit trusted-worker deploy/run/stop/quarantine
  lifecycle, failure threshold, explicit reset and per-run artifact integrity
  recheck. The pre-approved worker function does not load model weights.
- `experiments.py`: pinned dataset SHA-256, local seeded PRNG, reproducible
  error summaries and seeded bootstrap 95% confidence interval. Different
  datasets/sample counts cannot pass regression comparison.
- `device_replay.py`: seeded drop, duplication and positive receive jitter;
  source clock values never change. These are simulated observations only.
- `retention.py`: two-phase, explicitly approved deletion of old **derived**
  archival segments with legal-hold and retained-newest constraints. Do not run
  this on live sessions, mission evidence or concurrently modified directories.
- `spatial_evidence.py`: indexed SQLite observation provenance keyed by
  session, frame, timestamp, uncertainty, trace and calibration. Location
  hypothesis coordinates are optional and require an explicit local metric
  frame; the module never infers global GPS from image matches.
- `sdk_contract.py`: validated ROS 2-compatible `PoseStamped` data mapping
  with an *explicit* ROS time source and calibrated pose. This is a serializer,
  not a ROS network runtime or a flight-command bridge.

## Commands

```sh
swift test
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
PYTHONPATH=Toolkit python -m unittest discover -s ToolkitTests -p 'test_p2_*.py' -v
PYTHONPATH=Toolkit python -m aerospatial_tools model-check MODELS_DIR models.json
PYTHONPATH=Toolkit python -m aerospatial_tools experiment-errors errors.jsonl EXPECTED_SHA256 --seed 42
PYTHONPATH=Toolkit python -m aerospatial_tools retention-plan DERIVED_ARCHIVE --keep 2 --days 30 --now-ns 1770000000000000000
PYTHONPATH=Toolkit python -m aerospatial_tools replay-faults events.json --seed 42
```

The CLI retention command is strictly dry-run. Destructive approval is only
available through the explicit Python API after review of the exact plan hash.

## Engineering boundaries

- Real Core ML/Metal GPU selection and thermal-energy measurements require
  iPhone device profiling; the quality governor is not a real backend scheduler.
- The shipped model manager verifies bytes, not publisher signatures or
  arbitrary machine-code safety. Trusted-worker execution remains opt-in,
  limited and cannot run hostile plugins safely.
- ROS 2 serialization is not a network bridge. No ROS node executes on an
  aircraft through this library.
- Physical AirPods reference frames require measured extrinsics. An explicit
  time-valid transform registry cannot make unmeasured extrinsics true.
- ORB and RANSAC image matching do not prove metric SLAM, geolocation,
  scene identity or collision-free flight.
