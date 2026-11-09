#include "include/aerospatial_runtime.h"
#include <array>
#include <atomic>
#include <limits>
#include <new>

struct ASRuntimeMetrics {
    uint64_t deadline;
    std::array<std::atomic<uint64_t>, 64> bins{};
    std::atomic<uint64_t> samples{0};
    std::atomic<uint64_t> breaches{0};
    std::atomic<uint64_t> maximum{0};
    explicit ASRuntimeMetrics(uint64_t limit) : deadline(limit) {
        for (auto &bin : bins) bin.store(0, std::memory_order_relaxed);
    }
};

namespace {
unsigned bucket(uint64_t ns) {
    unsigned b = 0;
    while (ns >>= 1) ++b;
    return b;
}
uint64_t upper(unsigned b) {
    return b == 63 ? std::numeric_limits<uint64_t>::max() : ((uint64_t{1} << (b + 1)) - 1);
}
uint64_t percentile(const ASRuntimeMetrics &m, uint64_t samples, unsigned top, unsigned bottom) {
    if (!samples) return 0;
    const uint64_t target = samples / bottom * top + (samples % bottom * top + bottom - 1) / bottom;
    uint64_t sum = 0;
    for (unsigned i = 0; i < 64; ++i) {
        const auto observed = m.bins[i].load(std::memory_order_relaxed);
        sum = std::numeric_limits<uint64_t>::max() - sum < observed ?
              std::numeric_limits<uint64_t>::max() : sum + observed;
        if (sum >= target) return upper(i);
    }
    return m.maximum.load(std::memory_order_relaxed);
}
}
extern "C" ASRuntimeMetrics *as_runtime_metrics_create(uint64_t deadline_ns) {
    if (!deadline_ns) return nullptr;
    return new (std::nothrow) ASRuntimeMetrics(deadline_ns);
}
extern "C" void as_runtime_metrics_destroy(ASRuntimeMetrics *m) { delete m; }
extern "C" int as_runtime_metrics_record(ASRuntimeMetrics *m, uint64_t duration_ns) {
    if (!m) return 0;
    m->bins[bucket(duration_ns)].fetch_add(1, std::memory_order_relaxed);
    m->samples.fetch_add(1, std::memory_order_relaxed);
    if (duration_ns > m->deadline) m->breaches.fetch_add(1, std::memory_order_relaxed);
    uint64_t observed = m->maximum.load(std::memory_order_relaxed);
    while (duration_ns > observed &&
           !m->maximum.compare_exchange_weak(observed, duration_ns, std::memory_order_relaxed)) {}
    return 1;
}
extern "C" int as_runtime_metrics_report(const ASRuntimeMetrics *m, ASRuntimeReport *report) {
    if (!m || !report) return 0;
    const uint64_t count = m->samples.load(std::memory_order_relaxed);
    report->samples = count;
    report->breaches = m->breaches.load(std::memory_order_relaxed);
    report->maximum_ns = m->maximum.load(std::memory_order_relaxed);
    report->p95_upper_ns = percentile(*m, count, 95, 100);
    report->p99_upper_ns = percentile(*m, count, 99, 100);
    return 1;
}
extern "C" void as_runtime_metrics_reset(ASRuntimeMetrics *m) {
    if (!m) return;
    // Reset must be externally serialized against producers and reporters.
    for (auto &bin : m->bins) bin.store(0, std::memory_order_relaxed);
    m->samples.store(0, std::memory_order_relaxed);
    m->breaches.store(0, std::memory_order_relaxed);
    m->maximum.store(0, std::memory_order_relaxed);
}
