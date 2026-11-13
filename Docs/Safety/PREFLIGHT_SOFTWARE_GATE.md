# AeroSpatial preflight software gate — bounded replay and video EOS

This is a **software acceptance record**, not a certificate of DJI SDK hardware
compatibility, flightworthiness, calibrated positioning or stable mobile power.
The native C++ worker, video parser and online fusion remain observation-only.

## Correctness changes

1. `as_h264_access_finish_dual` provides clean-end tail NAL plus access-unit
   delivery without a second parse. A forced close/disconnect never flushes
   an unverified partial picture. `VideoPacketPublisher.finish()` is explicit
   and waits for the native worker to drain its admitted queue.
2. `as_fusion_position_replay` supports a validated late position update at an
   actual stored IMU timestamp. It retains at most 256 checkpoints, at most
   four position updates at each checkpoint, and rechecks all later previously
   accepted position corrections. On any failure state and accepted sequence
   remain unchanged. Ordinary current-time position updates remain efficient.
3. A long IMU gap invalidates the online estimator until fresh initialization.
   Subsequent IMU packets cannot make an invalid state silently become healthy.

## Reproducible portable test evidence

Run on the exact release source tree:

```sh
bash Scripts/run-checks.sh
cmake -S Kernel -B build-asan -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -O1" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
cmake --build build-asan --parallel
ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=print_stacktrace=1 \
  ctest --test-dir build-asan --output-on-failure
```

Portable acceptance must additionally include a **CI run on the exact commit**
for Linux/Windows core tests and the iOS simulator. The simulation build does
not compile DJI-specific symbols unless DJI Mobile SDK is linked.

## Cannot be declared passed without physical evidence

- SDK V4 linkage on a compatible Mac, signed iOS install and Mavic Air 2 link.
- Genuine DJI encoded callbacks, VideoToolbox pixel outputs, capture timing,
  GOP variation and reconnect loss/recovery under real conditions.
- Real AirPods/iPhone/aircraft source clock alignment, physical camera and
  body extrinsic calibration, available actual raw IMU, and GNSS accuracy.
- VO/SLAM accuracy on labeled real sequences, IMU–video fusion stability,
  scale observability, covariance consistency and real-world drift.
- Thermal/RSS/p95/p99 end-to-end latency and 24-hour soak on an iPhone.
- Propellers removed during any physical gimbal safety tests, independent
  controller ownership, watchdog and manual stop behavior.

Do not convert missing hardware evidence into a software pass, or infer raw
camera/IMU availability from an SDK callback or synthetic fixture.
