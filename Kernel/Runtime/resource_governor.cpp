#include "include/aerospatial_runtime.h"
#include <algorithm>
#include <memory>
#include <mutex>
#include <new>

namespace {
struct BudgetState {
    explicit BudgetState(uint64_t maximum) { report.limit_bytes = maximum; }
    mutable std::mutex mutex;
    ASResourceReport report{};
};
}
struct ASResourceGovernor {
    std::shared_ptr<BudgetState> state;
};
struct ASResourcePermit {
    std::shared_ptr<BudgetState> state;
    uint32_t kind;
    uint64_t bytes;
};
extern "C" ASResourceGovernor *as_resource_governor_create(uint64_t limit) {
    if (!limit || limit > (uint64_t{1} << 34)) return nullptr;
    try { return new ASResourceGovernor{std::make_shared<BudgetState>(limit)}; }
    catch (...) { return nullptr; }
}
extern "C" ASResourceGovernor *as_resource_governor_retain(const ASResourceGovernor *g) {
    if (!g) return nullptr;
    try { return new ASResourceGovernor{g->state}; }
    catch (...) { return nullptr; }
}
extern "C" void as_resource_governor_destroy(ASResourceGovernor *g) { delete g; }
extern "C" ASResourcePermit *as_resource_permit_acquire(ASResourceGovernor *g,
                                                        uint32_t kind, uint64_t bytes) {
    if (!g || kind >= AS_RESOURCE_CLASS_COUNT || !bytes) return nullptr;
    auto state = g->state;
    std::lock_guard<std::mutex> lock(state->mutex);
    auto &r = state->report;
    if (r.live_bytes > r.limit_bytes || bytes > r.limit_bytes - r.live_bytes) {
        ++r.rejected;
        return nullptr;
    }
    ASResourcePermit *permit = nullptr;
    try { permit = new ASResourcePermit{state, kind, bytes}; }
    catch (...) { ++r.rejected; return nullptr; }
    r.live_bytes += bytes;
    r.by_class_bytes[kind] += bytes;
    r.high_water_bytes = std::max(r.high_water_bytes, r.live_bytes);
    return permit;
}
extern "C" void as_resource_permit_release(ASResourcePermit *p) {
    if (!p) return;
    {
        std::lock_guard<std::mutex> lock(p->state->mutex);
        auto &r = p->state->report;
        r.live_bytes -= p->bytes;
        r.by_class_bytes[p->kind] -= p->bytes;
    }
    delete p;
}
extern "C" int as_resource_governor_report(const ASResourceGovernor *g, ASResourceReport *out) {
    if (!g || !out) return 0;
    std::lock_guard<std::mutex> lock(g->state->mutex);
    *out = g->state->report;
    return 1;
}
