#include "test_common.h"
#include "../Kernel/include/aerospatial_bus.h"
#include <atomic>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <thread>
#include <vector>

int main() {
    const uint64_t iterations = std::getenv("AEROSPATIAL_SOAK_EVENTS") ?
        std::strtoull(std::getenv("AEROSPATIAL_SOAK_EVENTS"), nullptr, 10) : 10000;
    REQUIRE(iterations >= 1 && iterations <= 5000000);
    ASBusConfig config{1, 4};
    auto *bus = as_bus_create(&config);
    REQUIRE(bus);
    REQUIRE(as_bus_set_payload_budget(bus, 192 * 1024) == ASBUS_OK);
    REQUIRE(as_bus_add_topic(bus, {ASBUS_HEAD, 128, 2048, ASBUS_OVERWRITE_OLDEST}) == ASBUS_OK);
    auto *writer = as_bus_open_publisher(bus, ASBUS_HEAD);
    auto *reader = as_bus_subscribe(bus, ASBUS_HEAD, 0);
    REQUIRE(writer && reader);
    std::atomic<uint64_t> accepted{0}, observed{0}, skipped{0};
    std::atomic<bool> complete{false};
    std::thread consumer([&] {
        std::array<uint8_t, 1024> payload{};
        ASBusHeader header{};
        uint64_t missed = 0;
        size_t bytes = 0;
        while (!complete.load(std::memory_order_acquire)) {
            auto status = as_bus_poll(reader, payload.data(), payload.size(), &header, &bytes, &missed);
            if (status == ASBUS_OK) {
                REQUIRE(bytes == payload.size());
                ++observed; skipped += missed;
            } else REQUIRE(status == ASBUS_EMPTY);
        }
        while (true) {
            auto status = as_bus_poll(reader, payload.data(), payload.size(), &header, &bytes, &missed);
            if (status == ASBUS_EMPTY) break;
            REQUIRE(status == ASBUS_OK);
            ++observed; skipped += missed;
        }
    });
    std::vector<std::thread> producers;
    for (int producer = 0; producer < 4; ++producer) {
        producers.emplace_back([&, producer] {
            std::array<uint8_t, 1024> payload{};
            payload[0] = static_cast<uint8_t>(producer);
            ASBusHeader header{};
            header.stream_id = ASBUS_HEAD;
            header.clock_domain = 1;
            header.quality_flags = ASBUS_QUALITY_VALID;
            header.timestamp_ns = 0; // Multiple producer clocks share a single source timestamp.
            for (uint64_t i = 0; i < iterations; ++i) {
                REQUIRE(as_bus_publish_fast(writer, header, payload.data(), payload.size()) == ASBUS_OK);
                ++accepted;
            }
        });
    }
    for (auto &producer : producers) producer.join();
    complete.store(true, std::memory_order_release);
    consumer.join();
    REQUIRE(accepted == 4 * iterations);
    REQUIRE(observed + skipped == accepted);
    ASBusMemoryStats memory{};
    ASBusTopicStats stats{};
    REQUIRE(as_bus_memory_stats(bus, &memory) == ASBUS_OK);
    REQUIRE(as_bus_stats(bus, ASBUS_HEAD, &stats) == ASBUS_OK);
    REQUIRE(memory.high_water_bytes <= memory.limit_bytes);
    REQUIRE(stats.published == accepted);
    REQUIRE(stats.invalid == 0 && stats.budget_rejected == 0);
    as_bus_unsubscribe(reader);
    as_bus_close_publisher(writer);
    as_bus_destroy(bus);
}
