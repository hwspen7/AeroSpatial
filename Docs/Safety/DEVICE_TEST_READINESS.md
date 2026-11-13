# Mavic Air 2 physical test readiness: evidence rather than assumed success

## What the software release can establish

- Linux Swift, C++, Python, sanitizers and iOS simulator compilation are automated.
- `.github/workflows/dji-sdk-compile.yml` now also builds the **actual DJI-linked iOS target** on push. This is a compile/link check; there is no aircraft attached to GitHub runners.
- `DecodedFrameEvidence` distinguishes accepted, stale, invalid and out-of-order decoded pixel buffers. It uses the **host receipt clock**, not camera exposure time.
- DJI poll-triggered link loss stops video reception and clears telemetry/capability evidence rather than waiting indefinitely for a disconnected callback.

## Required setup, no propellers installed

1. On a Mac with supported Xcode, clone the exact GitHub commit. Install XcodeGen and CocoaPods. Use `xcodegen generate && pod install` and build `AeroSpatial.xcworkspace` on **generic iOS device**. Verify the automatic DJI-linked CI job for the exact commit first.
2. Replace `DJISDKAppKey` in the **local** app Info.plist with the app key for the actual bundle ID. Do not commit the key. Configure signing for the connected iPhone. Verify that SDK registration succeeds on device.
3. With aircraft propellers removed, connect the Mavic Air 2 via its compatible remote. Confirm the precise model, firmware and SDK version. Keep physical remote control and manual STOP available. Avoid activating any experimental gimbal command until the bench safety gate has been independently checked.
4. Observe encoded callbacks, decoded access units, `CVPixelBuffer` counts and dimensions in app Diagnostics. A compiler success and an access-unit count alone do not prove decoded frames.
5. Start/stop and reconnect the stream repeatedly. Confirm stale video stops, no controls are granted from component presence, and new images require a valid keyframe.
6. Collect CPU/RSS, power/thermal, p95/p99 host receipt-to-decode duration and queue age with Instruments under sustained load. Do not label these as capture-to-display latency without separately measured source PTS.
7. For P1, determine **whether DJI actually exposes the required raw IMU**, then calibrate source clocks, camera intrinsics/extrinsics and ENU anchor from measured observations. Record real VO and ESKF errors against ground truth, including drift and failure cases. If raw IMU is absent, the IMU-dependent fusion requirement remains blocked and must use an independent validated sensor.

## Structural bench-evidence check

After collecting actual observations, prepare a private JSON file with the required fields in `Scripts/device-acceptance.py` and run:

```
python3 Scripts/device-acceptance.py /path/to/bench-evidence.json
```

A successful report means the claimed measurements are structurally complete, **not that the claims were independently authenticated**. The acceptance tool explicitly rejects missing data or synthetic-only reports. Do not commit private device identifiers, precise GPS traces, secret app keys or raw video containing bystanders.

## Non-negotiable boundary

P0/P1 hardware acceptance cannot be signed off by simulation, software CI, or repository source inspection. The exact release can be called *software preflight-ready* once its own CI is green. It cannot be called *device-validated* until the actual evidence above is collected and reviewed.
