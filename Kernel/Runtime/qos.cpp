#include "include/aerospatial_qos.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <mutex>
#include <new>

namespace {
struct Bucket {
    ASQosPolicy policy{};
    ASQosStats stats{};
    double tokens = 0;
    uint64_t last_time_ns = 0;
    bool configured = false;
    bool has_time = false;
};
constexpr uint32_t kMaxStream = 5;
constexpr double kMaxUnits = 1e12;
bool valid_stream(uint32_t stream) { return stream >= 3 && stream <= kMaxStream; }
}  // namespace

struct ASQosGovernor {
    std::mutex mutex;
    std::array<Bucket, kMaxStream + 1> streams{};
};

extern "C" ASQosGovernor *as_qos_create(void) {
    return new (std::nothrow) ASQosGovernor();
}
extern "C" void as_qos_destroy(ASQosGovernor *governor) { delete governor; }

extern "C" ASQosDecision as_qos_configure(ASQosGovernor *governor, ASQosPolicy policy) {
    if (!governor || !valid_stream(policy.stream_id) ||
        !std::isfinite(policy.refill_units_per_second) ||
        !std::isfinite(policy.burst_units) || policy.refill_units_per_second <= 0 ||
        policy.burst_units <= 0 || policy.refill_units_per_second > kMaxUnits ||
        policy.burst_units > kMaxUnits || policy.maximum_pressure_permille > 1000) {
        return ASQOS_INVALID;
    }
    std::lock_guard<std::mutex> lock(governor->mutex);
    auto &bucket = governor->streams[policy.stream_id];
    bucket = Bucket{};
    bucket.policy = policy;
    bucket.tokens = policy.burst_units;
    bucket.configured = true;
    return ASQOS_ADMITTED;
}

extern "C" ASQosDecision as_qos_admit(ASQosGovernor *governor, uint32_t stream_id,
                                       uint64_t timestamp_ns, double estimated_units,
                                       uint32_t pressure_permille) {
    if (!governor || !valid_stream(stream_id)) return ASQOS_INVALID;
    std::lock_guard<std::mutex> lock(governor->mutex);
    auto &bucket = governor->streams[stream_id];
    if (!bucket.configured) return ASQOS_INVALID;
    ++bucket.stats.seen;
    if (!std::isfinite(estimated_units) || estimated_units <= 0 ||
        estimated_units > bucket.policy.burst_units || pressure_permille > 1000) {
        ++bucket.stats.invalid;
        return ASQOS_INVALID;
    }
    if (bucket.has_time && timestamp_ns < bucket.last_time_ns) {
        ++bucket.stats.invalid;
        return ASQOS_TIME_REGRESSION;
    }
    if (bucket.has_time) {
        // Clamp elapsed time to one complete bucket refill, avoiding overflow
        // and inf arithmetic even after a long process suspension.
        const double elapsed = static_cast<double>(timestamp_ns - bucket.last_time_ns) * 1e-9;
        const double refill = bucket.policy.refill_units_per_second *
                              std::min(elapsed, bucket.policy.burst_units /
                                               bucket.policy.refill_units_per_second);
        bucket.tokens = std::min(bucket.policy.burst_units, bucket.tokens + refill);
    }
    bucket.last_time_ns = timestamp_ns;
    bucket.has_time = true;
    if (pressure_permille > bucket.policy.maximum_pressure_permille) {
        ++bucket.stats.backlogged;
        return ASQOS_BACKLOGGED;
    }
    if (bucket.tokens + 1e-9 < estimated_units) {
        ++bucket.stats.rate_limited;
        return ASQOS_RATE_LIMITED;
    }
    bucket.tokens = std::max(0.0, bucket.tokens - estimated_units);
    ++bucket.stats.admitted;
    return ASQOS_ADMITTED;
}

extern "C" ASQosDecision as_qos_stats(ASQosGovernor *governor, uint32_t stream_id,
                                       ASQosStats *result) {
    if (!governor || !result || !valid_stream(stream_id)) return ASQOS_INVALID;
    std::lock_guard<std::mutex> lock(governor->mutex);
    const auto &bucket = governor->streams[stream_id];
    if (!bucket.configured) return ASQOS_INVALID;
    *result = bucket.stats;
    result->available_units = bucket.tokens;
    return ASQOS_ADMITTED;
}
