#include "test_common.h"
#include "../Kernel/include/aerospatial_realtime.h"
#include <atomic>
#include <limits>
#include <thread>

static ASRealtimeHeadSample make_sample(int value) {
    return {double(value), double(value) / 2, -double(value), 0};
}
static void bounded_and_latest() {
    auto *queue = as_rt_head_create(3);
    REQUIRE(queue);
    REQUIRE(as_rt_head_create(1) == nullptr);
    for (int i = 0; i < 3; ++i) REQUIRE(as_rt_head_push(queue, make_sample(i)) == ASRT_OK);
    REQUIRE(as_rt_head_push(queue, make_sample(3)) == ASRT_FULL);
    ASRealtimeHeadSample result{};
    REQUIRE(as_rt_head_pop_latest(queue, &result) == ASRT_OK);
    REQUIRE(result.uptime_seconds == 2);
    REQUIRE(as_rt_head_pop(queue, &result) == ASRT_EMPTY);
    REQUIRE(as_rt_head_push(queue, {std::numeric_limits<double>::quiet_NaN(), 0, 0, 0}) == ASRT_INVALID);
    ASRealtimeQueueStats stats{};
    REQUIRE(as_rt_head_stats(queue, &stats) == ASRT_OK);
    REQUIRE(stats.accepted == 3 && stats.consumed == 3);
    REQUIRE(stats.coalesced == 2 && stats.rejected_full == 1 && stats.rejected_invalid == 1);
    as_rt_head_destroy(queue);
}
static void concurrent_single_writer_reader() {
    auto *queue = as_rt_head_create(127);
    REQUIRE(queue);
    std::atomic<bool> complete{false};
    std::thread producer([&]() {
        for (int i = 0; i < 100000; ++i) {
            while (as_rt_head_push(queue, make_sample(i)) == ASRT_FULL) std::this_thread::yield();
        }
        complete.store(true, std::memory_order_release);
    });
    int last = -1;
    while (!complete.load(std::memory_order_acquire) || last < 99999) {
        ASRealtimeHeadSample event{};
        if (as_rt_head_pop(queue, &event) == ASRT_OK) {
            REQUIRE(event.uptime_seconds == last + 1);
            last = int(event.uptime_seconds);
        } else std::this_thread::yield();
    }
    producer.join();
    REQUIRE(last == 99999);
    as_rt_head_destroy(queue);
}
static void continuous_latest_snapshot() {
    auto *queue = as_rt_head_create(127);
    REQUIRE(queue);
    std::atomic<bool> done{false};
    std::thread writer([&]() {
        for (int i = 0; i < 30000; ++i) {
            while (as_rt_head_push(queue, make_sample(i)) == ASRT_FULL)
                std::this_thread::yield();
        }
        done.store(true, std::memory_order_release);
    });
    int last = -1;
    while (!done.load(std::memory_order_acquire) || last < 29999) {
        ASRealtimeHeadSample sample{};
        if (as_rt_head_pop_latest(queue, &sample) == ASRT_OK) {
            REQUIRE(sample.uptime_seconds > last);
            last = int(sample.uptime_seconds);
        } else std::this_thread::yield();
    }
    writer.join();
    REQUIRE(last == 29999);
    as_rt_head_destroy(queue);
}

int main() {
    continuous_latest_snapshot();
    bounded_and_latest();
    concurrent_single_writer_reader();
}
