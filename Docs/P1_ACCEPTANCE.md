# P1 engineering acceptance matrix

P1 software is implemented as independently testable mathematical components.
There are **two different completion criteria**: portable implementation/tests,
and real hardware/data integration. CI success satisfies the former only.

| Original P1 area | Portable implementation | Automated evidence | Device / research gap |
| --- | --- | --- | --- |
| 9. Multisensor state estimation | 15D C++ ESKF, Swift adapter, offline position fusion | Native and Swift stationary/outlier tests | Raw IMU availability, precise GNSS/data clocks, measured noise |
| 10. Lie groups | SO(3)/SE(3) exponential, logarithm, rigid transforms | Native + Swift roundtrips | Body/camera/world extrinsic calibration |
| 11. Multirate/late samples | Bounded deterministic delayed observation replay | In-order vs late tests, sliding-window test | Live sensor rates, timestamp correlation |
| 12. Visual odometry | ORB/essential matrix, PnP, triangulation | Synthetic pinhole 3D point tests | Scene degeneracy/scale, actual images |
| 13. Robust local optimization | 6D pose graph, bundle adjustment + metric anchors | Reprojection and loop edge fixtures | Diverse real sequences, long trajectory drift |
| 14. Sparse 3D map | Bounded landmarks, voxel index, keyframe provenance | Query and invalid source tests | Metric mapping from actual camera and world datum |
| 15. Loop detection/graph | Existing ORB/RANSAC retrieval + metric-loop evidence validator | Conservative acceptance/rejection tests | Repeat-visit labeled dataset, loop false positives |
| 16. Uncertainty propagation | SE(3) adjoint, analytic camera-ray Jacobian, PSD/NEES | Finite-difference, covariance and statistical tests | Realistic camera/IMU/GNSS covariance calibration |
| 17. Motion prediction | Existing native CV Kalman + offline CV/CA model comparison | Synthetic known velocity/acceleration tests | Labeled targets and predictive calibration |
| 18. Camera calibration | Multi-view checkerboard solver; immutable registry exists | Known-intrinsics synthetic calibration fixture | Physical lens and crop/resolution measurements |

The foundation is for observation, diagnostics and optional research algorithms,
not flight authorization. It does not claim production-grade online SLAM,
metric monocular localization, live aerial navigation or global map accuracy.

## Future engineering integration (not silently declared complete)

- Actual Mavic Air 2 DJI SDK video access unit parsing and hardware decoding.
- Physical iPhone/AirPods/DJI timestamp and telemetry calibration.
- Continuous live inertial fusion with a device that exposes verified raw IMU.
- Deterministic, labeled multi-session VO/SLAM benchmark dataset with error bars.
- App-level model runtime lifecycle, durable map storage and true zero-copy
  CVPixelBuffer tracking.
- Fully vetted public plugin API compatibility and OS isolation for extensions.

Use `Docs/P1_SPATIAL_ESTIMATION.md` for the mathematical contracts and
`.github/workflows/core-tests.yml` for the reproducible acceptance suite.
