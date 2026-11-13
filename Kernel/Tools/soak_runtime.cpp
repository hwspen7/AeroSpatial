#include "aerospatial_bus.h"
#include "aerospatial_memory.h"
#include "aerospatial_runtime.h"
#include "aerospatial_work_queue.h"
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <vector>

namespace {
bool run(uint64_t count) {
    auto *budget = as_resource_governor_create(128 * 1024);
    if (!budget) return false;
    ASBusConfig config{1, 2};
    auto *bus = as_bus_create_budgeted(&config, budget);
    if (!bus) { as_resource_governor_destroy(budget); return false; }
    if (as_bus_set_payload_budget(bus, 64 * 1024) != ASBUS_OK ||
        as_bus_add_topic(bus, {ASBUS_HEAD, 8, 256, ASBUS_OVERWRITE_OLDEST}) != ASBUS_OK)
        return false;
    auto *pool = as_memory_pool_create_budgeted(64 * 1024, 256, budget);
    auto *queue = as_work_queue_create_budgeted(16, 64 * 1024, 256, budget);
    if (!pool || !queue) return false;
    std::array<uint8_t, 128> payload{};
    ASBusHeader bh{};
    bh.stream_id = ASBUS_HEAD;
    bh.clock_domain = 1;
    bh.quality_flags = ASBUS_QUALITY_VALID;
    for (uint64_t k = 0; k < count; ++k) {
        bh.timestamp_ns = k + 1;
        if (as_bus_publish(bus, bh, payload.data(), payload.size()) != ASBUS_OK) return false;
        auto *lease = as_memory_pool_copy(pool, payload.data(), payload.size());
        if (!lease) return false;
        if (k % 11 == 0) {
            auto *copy = as_memory_lease_retain(lease);
            if (!copy) return false;
            as_memory_lease_release(copy);
        }
        as_memory_lease_release(lease);
        ASWorkHeader wh{};
        wh.received_ns = k + 1;
        wh.deadline_ns = k + 1000;
        wh.priority = ASWQ_OPTIONAL;
        if (as_work_queue_push(queue, wh, payload.data(), payload.size(), k + 1) != ASWQ_OK)
            return false;
        ASWorkLease *out = nullptr;
        if (as_work_queue_pop_lease(queue, k + 1, &wh, &out) != ASWQ_OK) return false;
        as_work_lease_release(out);
        if ((k & 4095) == 0) {
            ASResourceReport report{};
            if (!as_resource_governor_report(budget, &report) ||
                report.high_water_bytes > report.limit_bytes ||
                report.live_bytes > 128 * 1024) return false;
        }
    }
    ASWorkStats qreport{};
    ASMemoryStats mreport{};
    if (!as_work_queue_stats(queue, &qreport) || qreport.queue_bytes ||
        !as_memory_pool_stats(pool, &mreport) || mreport.live_bytes)
        return false;
    as_work_queue_destroy(queue);
    as_memory_pool_destroy(pool);
    as_bus_destroy(bus);
    ASResourceReport final{};
    const bool success = as_resource_governor_report(budget, &final) &&
        final.live_bytes == 0 && final.rejected == 0 &&
        final.high_water_bytes <= final.limit_bytes;
    as_resource_governor_destroy(budget);
    return success;
}
}
int main(int argc, char **argv) {
    uint64_t iterations = 200000;
    if (argc > 2) return 2;
    if (argc == 2) {
        char *end = nullptr;
        iterations = std::strtoull(argv[1], &end, 10);
        if (!end || *end || iterations == 0 || iterations > 5000000) return 2;
    }
    // Multiple complete object lifecycles expose retained-permit leaks.
    for (int round = 0; round < 3; ++round)
        if (!run(iterations)) {
            std::fprintf(stderr, "runtime soak failed in round %d\n", round);
            return 1;
        }
    std::printf("runtime soak passed: 3 x %llu iterations\n",
                static_cast<unsigned long long>(iterations));
}
