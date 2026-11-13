# Spatial estimation foundation

The P1 library introduces reusable mathematical estimation components that are
**independent of DJI**. Only tested source code and synthetic/known-truth reference
experiments are delivered here. Neither aircraft inertial data availability nor
live video decoding is inferred from a successful portable unit test.

## Native C++17 kernel

`Kernel/include/aerospatial_estimation.h` exposes device-neutral C-compatible
functions. Every function validates finite inputs and returns explicit status codes.
The API deliberately has no camera SDK, control command, flight actuator, or
network dependency.

### SE(3) rigid body group

`as_pose_exp`, `as_pose_log`, `as_pose_compose` and `as_pose_inverse` operate on
child-to-parent rigid transforms. Twists use `[translation_m, rotation_rad]`.
The exponential maps the SO(3) rotation vector to a quaternion and the
translation using the SO(3) left Jacobian. The logarithm inverts this mapping
locally. The rotation order and quaternion layout agree with the existing
`ASQuaternion` convention `(w, x, y, z)`.

For **independent left-perturbation** uncertainties:

`Sigma_AB = Sigma_A + Ad(A) Sigma_B Ad(A)^T`

where `Ad(A) = [[R, skew(t) R], [0, R]]` and twist ordering is translation
before orientation. Input covariance matrices must be symmetric and PSD within
numeric tolerance. The operation computes a first-order covariance estimate,
not a global probability distribution.

### 15-dimensional error-state inertial estimator

Nominal state is `(p, v, q, b_a, b_g)` with a 15x15 row-major covariance for
`(delta p, delta v, delta theta, delta b_a, delta b_g)`. `q` rotates **body to
ENU**; specific force is in the body frame and angular velocity is in radians/s.
The world frame is right-handed ENU with gravity `(0, 0, -9.80665)` m/s^2.

Continuous nominal dynamics:

- `p_dot = v`
- `v_dot = R(q) (a_measured - b_a) + g`
- `q_dot = 1/2 q ⊗ omega_quaternion`
- Accelerometer and gyro biases are random walks in the error covariance.

Prediction implements the discrete first-order error Jacobian, position's
second-order coupling and discretized independent sensor noise. Measurement
updates use a three-dimensional position innovation, Mahalanobis/NIS gate,
Joseph covariance update and small-angle orientation-error reset. The update
returns an outlier status without changing the estimate when the gate fails.
No clock gaps are silently bridged; the caller must supply an independently
initialized pose and *actual raw, axis-calibrated* IMU measurements.

This is a mathematical navigation estimator, **not a full aircraft inertial
navigation system**. There is no automatic IMU initialization, magnetic/visual
heading initialization, automatic sensor bias observability guarantee, barometer
fusion, GNSS measurement transform, or DJI raw-IMU access claim. If Mavic Air 2
exposes only fused telemetry, do not connect it as raw IMU.

## Portable Swift API

`Core/Interop/NativeEstimation.swift` wraps native C++ operations with `SpatialPose3`,
`NativePoseMath`, `InertialNoise` and `InertialEstimator`. Error covariances use
15x15 row-major units. All estimation outputs are **observations** and never
issue gimbal or flight commands. Missing real source capabilities remain a
fail-closed condition.

## Offline visual mapping reference algorithms

These optional tools need the `mapping` extras (NumPy, SciPy and OpenCV):

| File | Capability | Important limitation |
| --- | --- | --- |
| `visual_geometry.py` | ORB correspondence, essential matrix RANSAC, PnP, parallax-gated triangulation | Monocular translation has unknown metric scale |
| `pose_graph.py` | Robust SE(3) relative-pose graph optimization with fixed first pose | Requires metric relative constraints, no automatic loop closures |
| `bundle_adjustment.py` | Huber loss reprojection bundle adjustment | Must fix first camera and one independently known metric landmark to resolve gauge |
| `sparse_map.py` | Provenance-aware keyframes, bounded landmarks, voxel spatial lookup | No learned descriptors, map georeferencing or persistent global index |
| `loop_closure.py` | Conservative metric loop edge validation | Image similarity alone never creates a metric pose constraint |
| `calibration_solver.py` | Multi-view checkerboard intrinsic/distortion calibration | Requires actual device image corners and diverse board poses |
| `fusion.py` | Fixed-lag replay of out-of-order position measurements | Accepts **ENU gravity-compensated** acceleration, not body-frame IMU |
| `uncertainty.py` | Jacobian covariance propagation for camera rays and 3D transformed points | Linearization assumptions, measured covariance required |
| `estimation_quality.py` | PSD checks, NEES and chi-square consistency | Statistical assumption and independent ground truth required |
| `motion_models.py` | BIC choice of constant velocity vs acceleration | A prediction is not a safety instruction |
| `spatial_demo.py` | Seeded camera/triangulation/PnP/bundle/graph experiment | Synthetic truth, not aerial field accuracy |

### Coordinate contracts

- Camera optical frame uses +X right, +Y down, +Z forward.
- All local world metric positions require an explicit origin and vertical datum.
- OpenCV `solvePnP` and bundle adjustment return **world-to-camera** poses;
  C++ `ASPose3` is **child-to-parent**. Convert/invert explicitly.
- Clock domains must be aligned using the existing `RobustClock` layer before
  associating pose, camera, GPS and AirPods observations.
- Use undistorted image points when a pinhole-only algorithm assumes them.
- A landmark, a scene match and a geographic target location are three
  different claims and must never be conflated.

## Reproducible verification

```bash
# Core portable modules, no third-party numerical dependencies
swift test
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release \
    -DAEROSPATIAL_BUILD_ESTIMATION_BENCHMARK=ON
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
./build-native/aerospatial-estimation-bench 20000

# Offline visual/optimization references with real NumPy/SciPy/OpenCV
python -m pip install -e '.[mapping]'
PYTHONPATH=. python -m unittest discover -s ToolkitTests -p '*_p1.py' -v
PYTHONPATH=. python -m aerospatial_tools spatial-demo --seed 42
```

Do not treat an optional-dependency skip as evidence the corresponding solver
ran. The spatial P1 CI job installs the mapping dependencies and executes all
spatial tests and the seeded fixture.

## Device closure gates

Physical iPhone/AirPods/Mavic Air 2 measurements must establish usable
sensor clocks, supported IMU fields, camera intrinsics and extrinsics, capture
timestamp provenance, GPS vertical datum and quantitative ground-truth errors.
Only then should an end-to-end sensor fusion/vision navigation system be marked
field-verified. The aircraft remains under its physical controller and all
experimental gimbal authorization is separate from this estimation layer.
