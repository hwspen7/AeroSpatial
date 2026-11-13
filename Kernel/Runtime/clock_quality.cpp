#include "include/aerospatial_runtime.h"
#include <array>
#include <mutex>
#include <new>

namespace {
struct ClockDomain {
    uint64_t source = 0;
    uint64_t mapped = 0;
    bool valid = false;
    ASClockReport stats{};
};
}
struct ASClockQuality {
    ASClockQuality(uint64_t age, uint64_t uncertainty, uint64_t jump)
        : maximum_age(age), maximum_uncertainty(uncertainty), maximum_jump(jump) {}
    const uint64_t maximum_age, maximum_uncertainty, maximum_jump;
    std::mutex mutex;
    std::array<ClockDomain, 3> domains{};
};
extern "C" ASClockQuality *as_clock_quality_create(uint64_t age, uint64_t uncertainty,
                                                      uint64_t jump) {
    if (!age || !uncertainty || !jump) return nullptr;
    return new (std::nothrow) ASClockQuality(age, uncertainty, jump);
}
extern "C" void as_clock_quality_destroy(ASClockQuality *q) { delete q; }
extern "C" int as_clock_quality_observe(ASClockQuality *q, uint32_t domain,
                                         uint64_t source, uint64_t mapped,
                                         uint64_t arrival, uint64_t uncertainty,
                                         ASClockReport *out) {
    if (!q || !out || domain < AS_CLOCK_AIRPODS || domain > AS_CLOCK_AIRCRAFT)
        return AS_CLOCK_INVALID;
    std::lock_guard<std::mutex> lock(q->mutex);
    auto &d = q->domains[domain - 1];
    int result = AS_CLOCK_ACCEPTED;
    const uint64_t age = arrival >= mapped ? arrival - mapped : mapped - arrival;
    if (!source || !mapped || !arrival) result = AS_CLOCK_INVALID;
    else if (d.valid && (source <= d.source || mapped <= d.mapped))
        result = AS_CLOCK_REGRESSION;
    else if (mapped > arrival || age > q->maximum_age)
        result = AS_CLOCK_STALE;
    else if (uncertainty > q->maximum_uncertainty)
        result = AS_CLOCK_UNCERTAIN;
    else if (d.valid) {
        const uint64_t source_delta = source - d.source;
        const uint64_t mapped_delta = mapped - d.mapped;
        const uint64_t divergence = source_delta > mapped_delta ?
            source_delta - mapped_delta : mapped_delta - source_delta;
        if (divergence > q->maximum_jump) result = AS_CLOCK_JUMP;
    }
    if (result == AS_CLOCK_ACCEPTED) {
        d.source = source;
        d.mapped = mapped;
        d.valid = true;
        ++d.stats.accepted;
        d.stats.last_age_ns = age;
        d.stats.last_uncertainty_ns = uncertainty;
        d.stats.has_anchor = 1;
    } else ++d.stats.rejected;
    *out = d.stats;
    return result;
}
extern "C" int as_clock_quality_reset(ASClockQuality *q, uint32_t domain) {
    if (!q || domain < AS_CLOCK_AIRPODS || domain > AS_CLOCK_AIRCRAFT) return 0;
    std::lock_guard<std::mutex> lock(q->mutex);
    auto &d = q->domains[domain - 1];
    d.source = d.mapped = 0;
    d.valid = false;
    d.stats.has_anchor = 0;
    return 1;
}
