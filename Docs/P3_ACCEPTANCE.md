# P3 engineering acceptance matrix

The P3 scope is defined in `Docs/P3_INTEGRATION.md`; no earlier P3 roadmap
existed. A passing software test does not establish deployed device operation.

| Deliverable | Software implementation | Portable acceptance | Hardware acceptance |
| --- | --- | --- | --- |
| Trusted CPU ONNX inference | Real OpenCV DNN graph evaluation, verified content digest, input/output limits | Tiny ONNX forward result and failure tests | Not relevant to CPU offline tests; target workload unmeasured |
| Optional Apple Core ML adapter | Verified `.mlmodel` compiler/loader and inference facade | Xcode iOS simulator build required | Actual signed iPhone/model benchmark not run |
| Video-to-place observations | Decode, ORB/RANSAC match, indexed SQLite evidence | Real encoded sample video tests, provenance and false-positive checks | Actual DJI hardware video still missing |
| Offline quality release gate | Missing, uncertain, weak and unverified metric evidence fail | Python negative tests | Labeled natural-scene accuracy not measured |
| Privacy-safe user export | Whitelisted numeric fields, re-based time, source integrity, explicit sharing | Portable Swift success/negative tests | Review iOS document sharing and privacy expectations |
| Developer diagnostics | UI exposes source drops and thermal-state indicator | iOS simulator build required | Instruments CPU/GPU/power profiling outstanding |
| ROS 2 observation bridge | Optional geometry_msgs publisher on external ROS node | Contract test with mocked ROS messages/node | DDS bridge compatibility not measured |

**Safety:** No new flight commands or gimbal actuation endpoints were
introduced. P3 math, perception, external API and diagnostic results cannot
authorize flight or alter the existing command gate.

**Outstanding:** End-to-end Mavic Air 2 and AirPods integration, genuine raw
IMU availability, device calibration, iPhone thermal and memory acceptance,
long-term environment change detection, actual real-time Core ML deployment,
and DJI SDK-specific hardware validation.

## Subsequent C++ runtime and video integration

- Portable C++ H.264 access-unit assembly and AVCC/SPS/PPS interface: implemented and tested on a genuine generated H.264 elementary stream, with seeded callback partitions.
- Native bounded priority/deadline work queue used by video ingress: implemented, native concurrency/overload tests and Swift bridge tests.
- iOS VideoToolbox sample conversion and serial decode path: source integrated, requires GitHub Xcode build and physical device decoder verification.
- Independent control cadence and lateness diagnostics: source integrated, still MainActor state-machine execution; physical latency and safety tests outstanding.

See `Docs/CPP_VIDEO_RUNTIME.md`. No physical completion is inferred.
