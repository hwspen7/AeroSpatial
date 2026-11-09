# Gimbal command safety contract

The normal iOS build has **no real gimbal output enabled**. All aircraft flight control remains outside the foundation.

## Command admission

`HeadTrackingController` performs bounded pitch mapping. `GimbalCommandGate` separately admits at most one pitch command at a time and requires an explicit application authorization, a connected non-flying aircraft, fresh head and aircraft samples, finite targets and an unlatched command path. Each admission issues a `(generation, sequence, issuedAt)` ticket.

A callback can complete **only** its exact ticket. Disarm, mode switch and explicit re-arm invalidate older generations. This prevents a delayed callback from authorizing subsequent writes. A callback failure or missing acknowledgment after the default one-second deadline latches an output fault and blocks new commands until explicit reset and operator re-arming. None of these gates cancels physical movement already accepted by the DJI gimbal.

## Sensor integrity

`SensorHealthMonitor` tracks monotonically increasing source timestamps, data shape, future samples, observed stream gaps and stale status. The application distinguishes a **link down event** from a fresh telemetry sample so a disconnection is always delivered, even if the prior telemetry timestamp has not advanced. Sensor checks do not certify attitude accuracy or locate obstacles.

`PassiveAdvisor` uses threshold hysteresis to prevent repeated battery warnings caused by sensor values fluctuating across a threshold. It remains informative only and cannot predict safe return power.

## Boundaries of proof

Swift XCTest, C++ CTest and Python audits validate the software behavior on synthetic or recorded data. They cannot establish: actual DJI SDK compatibility, RF link latency, motor stopping distance, AirPods timestamp validity on a specific iPhone, or suitability for flight. Real aircraft actuation stays confined to the explicitly gated, supervised propeller-off bench integration. See `HARDWARE_TEST_PLAN.md`.
