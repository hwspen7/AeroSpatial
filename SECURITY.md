# Security, privacy and safety

AeroSpatial is research/developer-preview software. **It is not approved flight-control software.** Drone flight, propellers, airspace and people pose real-world risks, and the stock controller and manufacturer safety features remain authoritative.

The standard build sends **no live gimbal commands** to DJI. The source contains an explicit developer-only propeller-off, nonflying bench option. Never fly with that experimental build. There are no virtual-stick, motor, takeoff, landing, mission or autonomous flight interfaces in this repository.

## Sensitive information

Recorded sessions can include geographic coordinates, headings and timestamps. Local SQLite memory can contain operator-entered labels and notes. Keep user data outside public repositories. `.gitignore` excludes JSONL recordings by default except committed synthetic fixtures, and excludes SQLite databases and local credentials. No Apple or DJI API credentials are bundled. Never post a DJI App Key, signing identity, personally identifying flight log, aircraft serial number or private location as an issue attachment.

## Reporting

If you discover an unintended real-aircraft command path, credentials exposure, unsafe actuator behavior or unauthorized data disclosure, do not post sensitive reproduction details publicly. Contact the repository owner through a private communication channel before public disclosure. Hardware test failures must be documented and block claims of flight readiness.

## Recorded telemetry and privacy

Raw session JSONL may contain aircraft coordinates and times. The `sanitize` CLI creates a separate privacy-reduced copy but does not guarantee removal of unknown user-defined location fields. Inspect exports before sharing. SHA-256 digest manifests detect accidental corruption but do not authenticate log provenance. Normal builds remain disarmed for live DJI output.
