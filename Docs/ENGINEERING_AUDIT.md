# Foundation engineering audit

The authoritative, item-by-item disposition of all 20 original findings is in [INTEGRATION_ACCEPTANCE.md](INTEGRATION_ACCEPTANCE.md). Portable tests do not establish aircraft acceptance.

## Changes introduced in the hardening pass

- Three deterministic allocation-failure checkpoints protect subscriber registration. A hidden expired-cursor statistic issue was discovered and fixed in `bus_consumer.cpp`.
- The C++ data bus now has a four-producer stress test with simultaneous reader and memory ceilings. Existing lease and global-budget tests remain mandatory.
- Fixed-size, checksum-validated, allocation-free native motion encoding has Swift and Python decoding and a cross-language probe.
- Explicit clock-error envelopes, bounded synthetic video ingress and trace-ID retention extend time-aware stream ingestion without claiming DJI video support.
- Versioned bus metadata migration and independently classified packet-loss provenance reduce ambiguity in diagnostics.
- Swift and Python implement matching CRC-framed segmented journals, with deterministic tail-repair and bounded rotation. The application-level recorder is still JSONL.
- Portable online latency histograms and native throughput gates are available to catch software regressions. On-device latency is unknown.

## Verification commands

```bash
bash Scripts/run-checks.sh
cmake -S Kernel -B build-bus -DCMAKE_BUILD_TYPE=Release -DAEROSPATIAL_BUILD_BUS_BENCHMARK=ON
cmake --build build-bus --parallel
AEROSPATIAL_SOAK_EVENTS=200000 ctest --test-dir build-bus -R native_bus_soak --output-on-failure
PYTHONPATH=Toolkit python3 -m aerospatial_tools.soak ./build-bus/aerospatial-bus-bench --payload 1024 --readers 4
```

Sanitizer CI additionally builds with AddressSanitizer and UndefinedBehaviorSanitizer. For real performance claims, measure the identical workload and toolchain on the **target iPhone**, not on the CI runner.
