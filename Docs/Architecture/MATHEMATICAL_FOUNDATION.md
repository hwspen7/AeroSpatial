# Numerical foundations and explicit limits

The portable algorithm library deliberately separates estimation from actuation. No
filter, image matcher, or clock fit in this document authorizes aircraft motion.
All values below are local estimates until validated with timestamped hardware logs.

## Affine clock alignment — C++ `calibration.cpp`, Swift `RobustClock.swift`

Source and host monotonic clocks are related by `t_host = a * t_source + b`.
A bounded Theil–Sen pairwise-median slope initializer resists sparse outliers.
The median offset supplies a robust location estimate. A least-squares refit on
residual-gated inliers estimates slope, intercept and RMS residual. The slope is
constrained by a configured maximum drift, and extrapolation is capped.

Estimated uncertainty is `RMS + extrapolated_seconds * drift_limit_ppm * 1e-6`.
This is **not** a certified probabilistic coverage bound or a replacement for
hardware timestamp calibration. Pairwise initialization costs O(n²) for at most
128 samples. Run calibration at low frequency, never inside the frame callback.

## Brown–Conrady optical model — C++ `calibration.cpp`, Swift `CameraLens.swift`

For normalized image coordinates `(x,y)` and `r²=x²+y²`, radial distortion is
`d=1+k1*r²+k2*r⁴+k3*r⁶`. Distorted coordinates are:

- `xd = x*d + 2*p1*x*y + p2*(r²+2*x²)`
- `yd = y*d + p1*(r²+2*y²) + 2*p2*x*y`

Pixel coordinates are `(fx*xd+cx, fy*yd+cy)`. The inverse uses analytic-Jacobian
Newton iterations, bounded to 16 steps with convergence and singularity checks.
A ray is a *direction*, not a 3D location. Distortion coefficients must be
measured for the actual lens, focus, frame size and crop; noninvertible extreme
coefficient configurations are rejected instead of returning arbitrary rays.

## Planar constant-velocity Kalman estimator — C++ `tracking.cpp`

Each horizontal axis has `state = [position, velocity]` and covariance `P`.
For timestep `dt`, the process model and continuous white-acceleration noise are:

```
F = [1 dt]       Q = q [dt³/3  dt²/2]
    [0  1]             [dt²/2  dt   ]
P_pred = F * P * Fᵀ + Q
```

For measured position with variance `R=sigma²`, the innovation `ν=z-H*x_pred`
uses `S=H*P_pred*Hᵀ+R`. Independent east/north observations are gated with
two-dimensional normalized innovation squared, `NIS=ν_e²/S_e+ν_n²/S_n`.
An outlier keeps the predicted state but does not update it with the bad sample.
A long observation gap triggers an explicit reset. This is not a full inertial
navigation filter, and a constant-velocity model may be wrong during turns.

## Visual place retrieval — `relocalization.py`

ORB produces binary feature descriptors. Hamming-distance k-NN matching with
Lowe's ratio filter removes ambiguous candidates. RANSAC then estimates a
shared 2D affine transformation and measures geometric inlier consistency.
Evidence links the query frame to a previously recorded image; it is *not* a
GPS fix, 3D pose estimate, reliable target identity or verified loop closure.
It should not be used for collision avoidance or autonomous flight. The
optional `vision` extras enable OpenCV and NumPy.

## Real video and provenance — `video_source.py` / `visual_memory.py`

The offline decoder bounds the number and size of decoded frames, preserves
presentation order and labels timestamps **estimated**. Uncertainty defaults
to half a nominal frame interval, which is a heuristic, not a guaranteed
sensor timing error. Image matches retain reference frame, observation frame,
inlier count and timestamp uncertainty. No optical calibration or DJI live
video connection is implied by the existence of an offline decoder.

## Security and performance boundaries

- `worker.py` runs *trusted* optional algorithms in isolated subprocesses with
  deadlines and input/output budgets. It is not a sandbox for hostile code.
  POSIX optional address-space and file-size limits are extra safeguards.
- `vault.py` uses AES-256-GCM authenticated encryption and an explicit grant
  for offline export; encryption keys remain the caller's responsibility.
- Mathematical kernel time complexity and release microbenchmarks are tracked
  separately. Desktop throughput never implies iOS thermal or flight latency.
- Global payload accounting still excludes some allocator metadata. The C++
  bus is mutex-synchronized, not hard-real-time or lock-free.

## Reproducibility commands

```
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
swift test
PYTHONPATH=. python -m unittest discover -s ToolkitTests -v
```
