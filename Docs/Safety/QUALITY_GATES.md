# Offline data-quality gates

Quality gates are designed for regression control and reproducible development, **not certification of flight safety**.

## Data integrity and semantic quality

`validate FILE` checks versioned event sequence continuity, nondecreasing uptime and the v1 format bounds. `audit FILE` runs explicit, reusable rules for sensor-to-command age, pitch-command envelope and outstanding command/callback relationships. Synthetic `simulator` commands are scheduling intentions and not evidence of a physical SDK write.

`gate FILE --profile Quality/simulator.json` applies machine-readable minimum sample counts and maximum permitted p95 sensor age and error budgets. **Missing required metrics fail closed.** The included profile is for the fixed Python simulator, not live aircraft logs.

```bash
PYTHONPATH=. python3 -m aerospatial_tools simulate /tmp/sim.jsonl --seconds 5 --seed 42
PYTHONPATH=. python3 -m aerospatial_tools gate /tmp/sim.jsonl --profile Quality/simulator.json
```

## Control-loop integration

The Swift `aerospatial-scenario` executable runs real portable components in virtual time: `SensorHealthMonitor`, `SensorSynchronizer`, `HeadTrackingController` and `GimbalCommandGate`. It produces v1 JSONL with synthetic acknowledgment callbacks. A configurable multi-second head dropout must disarm the controller and prohibit further commands without re-arming. Python can validate and audit the resulting trace without knowing Swift internals.

## Negative scenarios

`inject-fault` produces new files with `drop_record`, `duplicate_sequence`, `clock_regression` or `stale_head` corruption. CI tests verify that appropriate validators or semantic rules reject the damaged recordings. No fault injector is connected to DJI hardware.

## SHA-256 manifest

`digest create` and `digest verify` compare a recorded file against a stored size and SHA-256 digest to detect accidental truncation or modification. This is **not a signature**, cannot authenticate who recorded a file and cannot prevent an attacker from replacing both file and manifest.
