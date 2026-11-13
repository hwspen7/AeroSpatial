#include "test_common.h"
#include "../Kernel/include/aerospatial_work_queue.h"
#include <atomic>
#include <thread>
#include <vector>

static ASWorkHeader head(uint32_t priority, uint64_t trace, uint64_t deadline = 1000) {
    return {trace, 1, deadline, 7, priority};
}
int main() {
    auto *q = as_work_queue_create(3, 20, 12);
    REQUIRE(q);
    const uint8_t data[] = {1, 2, 3, 4, 5};
    REQUIRE(as_work_queue_push(q, head(ASWQ_OPTIONAL, 1), data, 5, 2) == ASWQ_OK);
    REQUIRE(as_work_queue_push(q, head(ASWQ_OPTIONAL, 2), data, 5, 2) == ASWQ_OK);
    REQUIRE(as_work_queue_push(q, head(ASWQ_OPTIONAL, 3), data, 5, 2) == ASWQ_OK);
    REQUIRE(as_work_queue_push(q, head(ASWQ_OPTIONAL, 4), data, 5, 2) == ASWQ_FULL);
    REQUIRE(as_work_queue_push(q, head(ASWQ_ESSENTIAL, 5), data, 5, 2) == ASWQ_OK);
    ASWorkStats stats{};
    REQUIRE(as_work_queue_stats(q, &stats));
    REQUIRE(stats.evicted_optional == 1);
    REQUIRE(stats.queue_events == 3 && stats.queue_bytes == 15);
    ASWorkHeader result{};
    uint8_t buffer[16]{};
    size_t length = 0;
    REQUIRE(as_work_queue_pop(q, 3, &result, buffer, 1, &length) == ASWQ_INVALID);
    REQUIRE(length == 5); // no partial dequeue
    REQUIRE(as_work_queue_pop(q, 3, &result, buffer, sizeof(buffer), &length) == ASWQ_OK);
    REQUIRE(result.trace_id == 5 && length == 5 && buffer[0] == 1);
    REQUIRE(as_work_queue_pop(q, 3, &result, buffer, sizeof(buffer), &length) == ASWQ_OK);
    REQUIRE(result.trace_id == 2);
    REQUIRE(as_work_queue_pop(q, 3, &result, buffer, sizeof(buffer), &length) == ASWQ_OK);
    REQUIRE(result.trace_id == 3);
    REQUIRE(as_work_queue_pop(q, 3, &result, buffer, sizeof(buffer), &length) == ASWQ_EMPTY);
    REQUIRE(as_work_queue_push(q, head(ASWQ_OPTIONAL, 9, 8), data, 5, 2) == ASWQ_OK);
    REQUIRE(as_work_queue_pop(q, 8, &result, buffer, sizeof(buffer), &length) == ASWQ_EMPTY);
    REQUIRE(as_work_queue_stats(q, &stats));
    REQUIRE(stats.expired == 1 && stats.maximum_queue_wait_ns == 1);
    REQUIRE(as_work_queue_push(q, head(ASWQ_ESSENTIAL, 10, 8), data, 5, 8) == ASWQ_EXPIRED);
    REQUIRE(as_work_queue_push(q, head(42, 11), data, 5, 2) == ASWQ_INVALID);
    REQUIRE(as_work_queue_push(q, head(ASWQ_ESSENTIAL, 11), data, 13, 2) == ASWQ_INVALID);
    as_work_queue_close(q);
    REQUIRE(as_work_queue_push(q, head(ASWQ_OPTIONAL, 12), data, 5, 2) == ASWQ_CLOSED);
    REQUIRE(as_work_queue_pop(q, 8, &result, buffer, sizeof(buffer), &length) == ASWQ_CLOSED);
    as_work_queue_destroy(q);

    // Concurrent optional workers and a separate producer never exceed capacity.
    q = as_work_queue_create(16, 80, 5);
    REQUIRE(q);
    std::atomic<uint64_t> accepted{0};
    std::vector<std::thread> writers;
    for (unsigned id = 0; id < 4; ++id) writers.emplace_back([&, id] {
        for (unsigned i = 0; i < 2000; ++i) {
            if (as_work_queue_push(q, head(ASWQ_OPTIONAL, id * 2000 + i), data, 5, 2) == ASWQ_OK)
                accepted.fetch_add(1);
        }
    });
    for (auto &thread : writers) thread.join();
    REQUIRE(as_work_queue_stats(q, &stats));
    REQUIRE(stats.accepted == accepted.load());
    REQUIRE(stats.queue_events <= 16 && stats.queue_bytes <= 80);
    REQUIRE(stats.high_water_events <= 16 && stats.high_water_bytes <= 80);
    as_work_queue_destroy(q);
    REQUIRE(as_work_queue_create(0, 10, 5) == nullptr);
}
