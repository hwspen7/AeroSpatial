# Contributing

Use small, focused modules. Keep individual source files around or below 200 lines whenever practical, and separate C++ algorithms, Swift runtime/adapters and Python offline tooling. Code, identifiers and comments are in English. Document units, coordinate conventions, uncertainty and sensor provenance.

Before submitting changes, run `./Scripts/run-checks.sh` (or the relevant C++/Python checks on Windows). Add a regression test for each bug, particularly clock regression, stale data, missing calibration, disconnection and invalid geometry. For C++ ABI changes, update the public header, Swift wrapper, CMake tests and Python parity fixtures together. Never add aircraft flight commands as an incidental extension to gimbal features.

Avoid putting credentials, generated artifacts, personal JSONL sessions or local SQLite stores into Git history. Hardware compatibility and measured latency require verifiable model/firmware/OS evidence, not simulator assertions.
