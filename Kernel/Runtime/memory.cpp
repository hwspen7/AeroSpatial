#include "include/aerospatial_memory.h"
#include "include/aerospatial_runtime.h"
#include <algorithm>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <vector>

struct MemoryShared {
    explicit MemoryShared(size_t budget, size_t max_payload,
                          ASResourceGovernor *shared = nullptr)
        : limit(budget), maximum_payload(max_payload),
          governor(as_resource_governor_retain(shared)) {}
    ~MemoryShared() { as_resource_governor_destroy(governor); }
    ASResourceGovernor *governor = nullptr;
    std::mutex mutex;
    size_t limit, maximum_payload;
    ASMemoryStats stats{};
};
struct ASMemoryPool {
    explicit ASMemoryPool(size_t budget, size_t payload,
                          ASResourceGovernor *shared = nullptr)
        : state(std::make_shared<MemoryShared>(budget, payload, shared)) {}
    std::shared_ptr<MemoryShared> state;
};
struct LeaseBuffer {
    std::shared_ptr<MemoryShared> owner;
    std::vector<uint8_t> bytes;
    bool charged = false;
    ASResourcePermit *permit = nullptr;
    ~LeaseBuffer() {
        as_resource_permit_release(permit);
        if (!charged) return;
        std::lock_guard<std::mutex> guard(owner->mutex);
        owner->stats.live_bytes -= bytes.size();
        --owner->stats.allocated_leases;
    }
};
struct ASMemoryLease {
    std::shared_ptr<LeaseBuffer> buffer;
};

extern "C" ASMemoryPool *as_memory_pool_create(size_t budget, size_t payload) {
    if (budget == 0 || budget > (512u << 20) || payload == 0 || payload > budget ||
        payload > (64u << 20)) return nullptr;
    try { return new ASMemoryPool(budget, payload); }
    catch (...) { return nullptr; }
}
extern "C" ASMemoryPool *as_memory_pool_create_budgeted(
    size_t budget, size_t payload, ASResourceGovernor *governor) {
    if (!governor || budget == 0 || budget > (512u << 20) ||
        payload == 0 || payload > budget || payload > (64u << 20)) return nullptr;
    try {
        auto *pool = new ASMemoryPool(budget, payload, governor);
        if (!pool->state->governor) { delete pool; return nullptr; }
        return pool;
    } catch (...) { return nullptr; }
}
extern "C" void as_memory_pool_destroy(ASMemoryPool *pool) { delete pool; }
extern "C" ASMemoryLease *as_memory_pool_copy(ASMemoryPool *pool,
                                               const uint8_t *bytes, size_t length) {
    if (!pool || !bytes || !length) return nullptr;
    auto owner = pool->state;
    std::lock_guard<std::mutex> guard(owner->mutex);
    if (length > owner->maximum_payload || length > owner->limit - owner->stats.live_bytes) {
        ++owner->stats.rejected;
        return nullptr;
    }
    ASResourcePermit *permit = nullptr;
    if (owner->governor) {
        permit = as_resource_permit_acquire(owner->governor, AS_RESOURCE_POOL, length);
        if (!permit) { ++owner->stats.rejected; return nullptr; }
    }
    try {
        auto buffer = std::make_shared<LeaseBuffer>();
        buffer->owner = owner;
        buffer->permit = permit;
        permit = nullptr;
        buffer->bytes.assign(bytes, bytes + length);
        auto *lease = new ASMemoryLease{std::move(buffer)};
        owner->stats.live_bytes += length;
        lease->buffer->charged = true;
        owner->stats.high_water_bytes = std::max(owner->stats.high_water_bytes,
                                                   owner->stats.live_bytes);
        ++owner->stats.allocated_leases;
        return lease;
    } catch (...) {
        as_resource_permit_release(permit);
        ++owner->stats.rejected;
        return nullptr;
    }
}
extern "C" ASMemoryLease *as_memory_lease_retain(const ASMemoryLease *lease) {
    if (!lease || !lease->buffer) return nullptr;
    try { return new ASMemoryLease{lease->buffer}; } catch (...) { return nullptr; }
}
extern "C" void as_memory_lease_release(ASMemoryLease *lease) { delete lease; }
extern "C" const uint8_t *as_memory_lease_data(const ASMemoryLease *lease, size_t *length) {
    if (!lease || !lease->buffer || !length) return nullptr;
    *length = lease->buffer->bytes.size();
    return lease->buffer->bytes.data();
}
extern "C" int as_memory_pool_stats(const ASMemoryPool *pool, ASMemoryStats *out) {
    if (!pool || !out) return 0;
    std::lock_guard<std::mutex> guard(pool->state->mutex);
    *out = pool->state->stats;
    return 1;
}
