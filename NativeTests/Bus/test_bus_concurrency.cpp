#include "test_common.h"
#include "../Kernel/include/aerospatial_bus.h"
#include <atomic>
#include <cstdint>
#include <thread>
#include <vector>

int main() {
    ASBusConfig config{2, 4};
    auto *bus = as_bus_create(&config);
    REQUIRE(bus);
    REQUIRE(as_bus_add_topic(bus, {ASBUS_HEAD, 512, 8, ASBUS_OVERWRITE_OLDEST}) == ASBUS_OK);
    auto *reader = as_bus_subscribe(bus, ASBUS_HEAD, 1);
    REQUIRE(reader);
    std::atomic<uint64_t> finished{0};
    std::atomic<uint64_t> total_reads{0};
    std::atomic<uint64_t> last_seq{0};
    std::thread consumer([&] {
        while (true) {
            uint64_t payload = 0, missed = 0;
            ASBusHeader hdr{};
            size_t bytes = 0;
            auto status = as_bus_poll(reader, &payload, sizeof(payload), &hdr, &bytes, &missed);
            if (status == ASBUS_OK) {
                REQUIRE(hdr.sequence > last_seq.load());
                last_seq.store(hdr.sequence);
                REQUIRE(bytes == 8);
                ++total_reads;
            } else {
                REQUIRE(status == ASBUS_EMPTY);
                if (finished.load(std::memory_order_acquire)) break;
            }
            std::this_thread::yield();
        }
    });
    std::vector<std::thread> producers;
    for (uint64_t p = 0; p < 4; ++p) {
        producers.emplace_back([&, p] {
            for (uint64_t i = 0; i < 5000; ++i) {
                const uint64_t value = (p << 32) | i;
                ASBusHeader hdr{};
                hdr.timestamp_ns = 42; // Same monotonic timestamp across producers.
                hdr.stream_id = ASBUS_HEAD;
                hdr.clock_domain = 1;
                hdr.quality_flags = ASBUS_QUALITY_VALID;
                REQUIRE(as_bus_publish(bus, hdr, &value, 8) == ASBUS_OK);
            }
        });
    }
    for (auto &thread : producers) thread.join();
    finished.store(1, std::memory_order_release);
    consumer.join();
    ASBusTopicStats stats{};
    REQUIRE(as_bus_stats(bus, ASBUS_HEAD, &stats) == ASBUS_OK);
    REQUIRE(stats.published == 20000);
    REQUIRE(total_reads > 0);
    REQUIRE(stats.retained_events == 512);
    as_bus_unsubscribe(reader);
    as_bus_destroy(bus);
    return 0;
}
