# P0 acceptance and outstanding physical gates

This document is an **evidence register**, not a declaration of aircraft readiness.
An in-memory event is not a decoded video frame. A successful SDK registration
is not proof of hardware compatibility. Do not substitute a simulator for a drone.

## Portable source capabilities

| P0 requirement | Portable implementation | Current software evidence | Physical closure gate |
| --- | --- | --- | --- |
| Real-time ingress | Bounded Swift queues, native pub/sub, fail-visible counters | Swift ingress tests | iPhone p95/p99 age and queue drops under load |
| Video input | DJI V4 listener behind SDK guard, serial callback queue, bounded chunks, single-pass C++ NAL/access-unit assembly, AVCC VideoToolbox bridge | CTest native_h264, Swift NAL and packet tests | DJI SDK compile and true Mavic Air 2 encoded feed; decoder access-unit/frame tests |
| Clock alignment | Bounded robust affine fit with uncertainty and explicit clock domain | Swift clock tests | Paired hardware timestamp measurements for each source |
| Device capability discovery | SDK model check, observed component evidence, strict unverified state | Swift model/evidence tests | Firmware, device features and supported axes verified on a physical aircraft |
| Durable recording | CRC-framed segment archive, background admission, validated JSONL export | Swift recovery/corruption tests | Application crash, restart, full storage and retention on an iPhone |
| Safety supervision | Fail-closed clock, authorization, disconnection, freshness and pitch capability | Portable tests | Propellers-removed stationary gimbal bench, STOP and reconnection tests |
| Performance governance | Native atomic histogram, bounded overload policies, benchmark harness | CTest runtime metrics, Swift budget tests | Sustained mobile thermals/CPU/RSS/latency profile |
| Continuous validation | Linux Swift/C++/Python, Windows C++, sanitizer, automatic iOS simulator | CI workflows configured; run results separately | SDK-linked build and signed physical device tests |

## Critical video semantics

The DJI listener receives arbitrary encoded **byte fragments**, not access
units or `CMSampleBuffer` frames. The C++ Annex-B NAL parser now shares
its incremental pass with a bounded access-unit assembler, SPS/PPS handling and AVCC conversion. Normal
end-of-stream flushes a trailing picture; interrupted streams discard the
untrusted tail. Published diagnostics use kind `0x200 | nal_type`. Encoded
access units reach an optional VideoToolbox bridge, but decoded frames and
camera exposure timestamps are not confirmed on a physical Mavic Air 2.
Receipt timestamps use the host monotonic clock and carry `clockEstimated` and `lowConfidence` flags.
Lost chunks set `upstreamGap`, reset the parser and require decoder resync.

DJI SDK symbols are guarded by `#if canImport(DJISDK)`, which means the
simulation-only iOS build does **not** verify DJI SDK source compatibility.
Use `.github/workflows/dji-sdk-compile.yml` for the separate manual SDK build.
This workflow also does not count as real hardware validation.

## Reproduce software tests

```sh
swift test
cmake -S Kernel -B build-native -DCMAKE_BUILD_TYPE=Release
cmake --build build-native --parallel
ctest --test-dir build-native --output-on-failure
PYTHONPATH=. python3 -m unittest discover -s ToolkitTests
```

## Mandatory physical acceptance record

For each applicable gate record the device model, hardware identifiers where
appropriate, firmware and OS versions, DJI SDK version, test timestamp, operator,
measured source timestamps, expected/observed outcomes, CPU/GPU/RSS and p95/p99
latencies, deliberate fault injections, and a reproducible diagnostic log.

Never mark a physical gate passed without collected physical evidence. In
particular: remove propellers and use a stationary bench for authorized gimbal
experiments. Flight commands and autonomous control are not part of P0.
