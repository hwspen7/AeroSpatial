# Hardware acceptance plan — DJI Mavic Air 2

**Current state: NOT RUN.** Passing Swift unit tests does not satisfy any of the hardware gates below.

## Gate A — software compatibility

- [ ] Record Mac model, Xcode version, iOS version, AirPods model, aircraft model/firmware and controller model/firmware.
- [ ] Generate the Xcode project and compile the **simulation-only** iOS app successfully.
- [ ] Install `DJI-SDK-iOS` 4.16.2 with CocoaPods and open the workspace.
- [ ] Confirm DJI Swift module compilation, app registration, exact bundle ID and App Key.
- [ ] Confirm SDK reports exactly `Mavic Air 2`. An Air 2S, Mavic Air or unknown model must fail closed in the initial adapter.
- [ ] Confirm signed physical-iPhone launch; no simulator is claimed as live hardware testing.

## Gate B — passive hardware telemetry

- [ ] **Remove propellers physically**. Keep aircraft stationary on a clear surface and motors stopped.
- [ ] Connect the controller, start the application, observe DJI product and battery telemetry.
- [ ] Unplug the controller and verify connection state becomes disconnected and controls disarm.
- [ ] Repeat connect/disconnect 10 times and record outcomes.
- [ ] Verify data source says `dji` only when hardware is actually connected.
- [ ] Verify DJI's official application is not competing for control during SDK use.

## Gate C — headphone and sensor behavior

- [ ] Confirm `CMHeadphoneMotionManager.isDeviceMotionAvailable` on physical AirPods.
- [ ] Confirm the permission prompt appears and does not crash the app.
- [ ] Measure sample uptime monotonicity and head-pose axis sign by physically moving the headset.
- [ ] Validate lost-connection recovery and >400 ms loss watchdog.
- [ ] Verify that no motion input is treated as absolute geographic heading.

## Gate D — pitch-only gimbal bench test

**Important:** Standard builds cannot transmit live DJI gimbal commands. The explicit local-only `AEROSPATIAL_EXPERIMENTAL_BENCH` compile condition is necessary for these tests. Do not enable the flag in distributed builds or fly an aircraft using the bench build.

- [ ] Aircraft is **not flying**, propellers remain removed, gimbal has clearance throughout the test.
- [ ] Confirm pitch telemetry and supported pitch angle limits from DJI SDK for this particular model.
- [ ] Calibrate at a neutral position. Do not arm until a separate operator action.
- [ ] Command ±5° head movement first. Verify direction and correct `Invert pitch` option.
- [ ] Verify app's −85°…0° limits and 20°/s software slew limiter.
- [ ] Verify no yaw, roll, motor or flight-control commands are sent.
- [ ] Disconnect AirPods, disconnect controller, send malformed/old samples, background app, and press STOP. Verify assistance disarms.
- [ ] Measure total command latency, jitter, callback failures and any motion continuing after STOP.
- [ ] Do **not** enable live-control-in-flight unless a qualified operator reviews these results and establishes a separate operational safety procedure.

## Evidence to capture

Use JSONL session logs and a separate checklist with test timestamp, software versions, firmware versions, expected/actual behavior, errors and recovery steps. Report exact limitations. Mark each hardware gate pass only after actual measurement.
