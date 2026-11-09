#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
swift test
PYTHONPATH=Toolkit python3 -m aerospatial_tools bus-audit Fixtures/multimodal.jsonl
swift run aerospatial-replay Fixtures/session.jsonl
SCENARIO="$(mktemp /tmp/aerospatial-swift-scenario-XXXXXX.jsonl)"
trap 'rm -f "$SCENARIO"' EXIT
swift run aerospatial-scenario "$SCENARIO" 5 42 2
PYTHONPATH=Toolkit AEROSPATIAL_NATIVE_PROBE="$(pwd)/build-native/aerospatial-native-probe" \
  python3 -m unittest discover -s ToolkitTests -v
PYTHONPATH=Toolkit python3 -m aerospatial_tools validate Fixtures/session.jsonl
PYTHONPATH=Toolkit python3 -m aerospatial_tools validate "$SCENARIO"
PYTHONPATH=Toolkit python3 -m aerospatial_tools audit "$SCENARIO"
