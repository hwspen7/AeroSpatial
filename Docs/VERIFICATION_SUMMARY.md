# P0 implementation verification summary

**Target:** portable source and experimental DJI Mavic Air 2 adapter.
**Platform:** Linux local verification, November 9, 2026.

## Verified in the portable environment

- Swift portable package: `swift test` passed, including NAL parser Swift/C++ integration,
  packet discontinuities, recording recovery, and bounded observation ingress.
- C++ native suite: `ctest` passed, including deterministic 64-way split/merge
  testing for H.264 Annex-B syntax and all existing resource-limit checks.
- Python offline suite: all executed tests passed; optional dependencies may
  cause individual tests to be skipped on machines without those extras.
- AddressSanitizer / UndefinedBehaviorSanitizer: the native suite passed.
- `swiftc -frontend -parse App/*.swift` passed on Linux. **This does not
  substitute for Xcode typechecking of Apple/DJI SDK modules.**

## Material changes

1. The previous unpushed CRC-journal/application recorder fixes are incorporated.
2. DJI's V4 video feed is listened to on a named background dispatch queue,
   with registration on supported-model connect and removal on disconnect.
3. The bounded Swift packet source uses receiver monotonic timestamps,
   explicitly marked as estimated rather than true camera capture timestamps.
4. C++ parses H.264 Annex-B NAL units across arbitrary callback boundaries.
   A NAL unit is not a complete frame or video decoder output.
5. SDK-observed component presence remains unverified evidence. Pitch
   authorization requires verified capability and is never derived from
   mere model identification.
6. The runtime ingress exposes drop/publication counters to aid overload diagnosis.

## Not verified and not closed

- DJI V4 SDK-linked iOS build **with the DJI CocoaPods framework present**.
  The separate manual GitHub workflow is provided for this.
- Hardware H.264 source behavior, SPS/PPS and access-unit reassembly, and
  actual VideoToolbox decoder input for a Mavic Air 2 camera.
- Actual AirPods head timestamp accuracy, callback jitter or drift.
- DJI firmware capability probes or verified gimbal-pitch support.
- Signed physical iPhone build, propeller-off bench, device reconnects or
  full-duration mobile thermal and memory soak tests.

No autonomous flight functionality, flight control commands or in-flight
hardware tests have been added. **Hardware P0 must not be marked complete**
until the above measurements have been conducted on actual devices.
