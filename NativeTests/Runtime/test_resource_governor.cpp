#include "test_common.h"
#include "aerospatial_runtime.h"
#include "aerospatial_bus.h"
#include "aerospatial_memory.h"
#include "aerospatial_work_queue.h"
#include <array>
#include <atomic>
#include <thread>
#include <vector>

int main() {
    REQUIRE(as_resource_governor_create(0) == nullptr);
    auto *governor = as_resource_governor_create(300);
    REQUIRE(governor);
    auto *audit = as_resource_governor_retain(governor);
    REQUIRE(audit);
    ASBusConfig bc{1, 2};
    auto *bus = as_bus_create_budgeted(&bc, governor);
    REQUIRE(bus);
    REQUIRE(as_bus_set_payload_budget(bus, 256) == ASBUS_OK);
    REQUIRE(as_bus_add_topic(bus, {ASBUS_HEAD, 2, 100, ASBUS_REJECT_NEWEST}) == ASBUS_OK);
    ASBusHeader bh{};
    bh.stream_id = ASBUS_HEAD; bh.clock_domain = 1;
    bh.quality_flags = ASBUS_QUALITY_VALID; bh.timestamp_ns = 10;
    std::array<uint8_t, 100> bytes{};
    REQUIRE(as_bus_publish(bus, bh, bytes.data(), 80) == ASBUS_OK);
    auto *pool = as_memory_pool_create_budgeted(200, 150, governor);
    REQUIRE(pool);
    auto *lease = as_memory_pool_copy(pool, bytes.data(), 100);
    REQUIRE(lease);
    auto *retained = as_memory_lease_retain(lease);
    REQUIRE(retained);
    auto *queue = as_work_queue_create_budgeted(8, 200, 100, governor);
    REQUIRE(queue);
    ASWorkHeader wh{};
    wh.received_ns = 1; wh.deadline_ns = 100; wh.priority = ASWQ_OPTIONAL;
    REQUIRE(as_work_queue_push(queue, wh, bytes.data(), 50, 2) == ASWQ_OK);
    auto *video = as_resource_permit_acquire(governor, AS_RESOURCE_VIDEO, 40);
    REQUIRE(video);
    ASResourceReport snapshot{};
    REQUIRE(as_resource_governor_report(audit, &snapshot));
    REQUIRE(snapshot.live_bytes == 270 && snapshot.high_water_bytes == 270);
    REQUIRE(snapshot.by_class_bytes[AS_RESOURCE_BUS] == 80);
    REQUIRE(snapshot.by_class_bytes[AS_RESOURCE_POOL] == 100);
    REQUIRE(snapshot.by_class_bytes[AS_RESOURCE_WORK] == 50);
    REQUIRE(snapshot.by_class_bytes[AS_RESOURCE_VIDEO] == 40);
    REQUIRE(as_resource_permit_acquire(governor, AS_RESOURCE_VIDEO, 31) == nullptr);
    REQUIRE(as_resource_governor_report(audit, &snapshot) && snapshot.rejected == 1);
    REQUIRE(as_memory_pool_copy(pool, bytes.data(), 90) == nullptr);
    REQUIRE(as_bus_publish(bus, bh, bytes.data(), 80) == ASBUS_MEMORY_BUDGET);
    ASWorkLease *work = nullptr;
    REQUIRE(as_work_queue_pop_lease(queue, 3, &wh, &work) == ASWQ_OK);
    REQUIRE(work);
    // Dequeued memory remains charged until the consumer releases its lease.
    REQUIRE(as_resource_governor_report(audit, &snapshot) && snapshot.live_bytes == 270);
    as_resource_governor_destroy(governor);
    as_bus_destroy(bus);
    as_memory_pool_destroy(pool);
    as_work_queue_destroy(queue);
    REQUIRE(as_resource_governor_report(audit, &snapshot) && snapshot.live_bytes == 190);
    as_memory_lease_release(lease);
    REQUIRE(as_resource_governor_report(audit, &snapshot) && snapshot.live_bytes == 190);
    as_memory_lease_release(retained);
    as_work_lease_release(work);
    as_resource_permit_release(video);
    REQUIRE(as_resource_governor_report(audit, &snapshot));
    REQUIRE(snapshot.live_bytes == 0);
    for (auto value : snapshot.by_class_bytes) REQUIRE(value == 0);
    as_resource_governor_destroy(audit);

    auto *concurrent = as_resource_governor_create(1024);
    REQUIRE(concurrent);
    std::atomic<bool> stop{false};
    std::vector<std::thread> threads;
    for (int i = 0; i < 8; ++i) threads.emplace_back([&, i] {
        for (int round = 0; round < 20000; ++round) {
            auto *p = as_resource_permit_acquire(
                concurrent, static_cast<uint32_t>(i % AS_RESOURCE_CLASS_COUNT), 32);
            if (p) {
                if ((round % 17) == 0) std::this_thread::yield();
                as_resource_permit_release(p);
            }
        }
    });
    for (auto &thread : threads) thread.join();
    REQUIRE(as_resource_governor_report(concurrent, &snapshot));
    REQUIRE(snapshot.live_bytes == 0 && snapshot.high_water_bytes <= 1024);
    as_resource_governor_destroy(concurrent);
}
