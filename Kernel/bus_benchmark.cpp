#include "include/aerospatial_bus.h"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

int main(int argc, char **argv) {
    const uint64_t count = argc > 1 ? std::strtoull(argv[1], nullptr, 10) : 500000;
    const size_t payload_bytes = argc > 2 ? std::strtoull(argv[2], nullptr, 10) : 8;
    const uint32_t readers = argc > 3 ? static_cast<uint32_t>(std::strtoul(argv[3], nullptr, 10)) : 0;
    const bool fast = argc > 4 ? std::strcmp(argv[4], "fast") == 0 : true;
    if (!count || count > 20000000 || !payload_bytes || payload_bytes > 65536 || readers > 16)
        return 2;
    ASBusConfig config{4, 16};
    ASBus *bus = as_bus_create(&config);
    if (!bus || as_bus_add_topic(bus, {ASBUS_HEAD, 1024, 65536, ASBUS_OVERWRITE_OLDEST}) != ASBUS_OK)
        return 2;
    auto *writer = as_bus_open_publisher(bus, ASBUS_HEAD);
    if (!writer) return 2;
    std::vector<ASBusSubscription *> subscriptions;
    for (uint32_t i = 0; i < readers; ++i) {
        auto *subscription = as_bus_subscribe(bus, ASBUS_HEAD, 1);
        if (!subscription) return 2;
        subscriptions.push_back(subscription);
    }
    std::vector<uint8_t> data(payload_bytes, 0x5A);
    ASBusHeader header{};
    header.stream_id = ASBUS_HEAD;
    header.clock_domain = 1;
    header.quality_flags = ASBUS_QUALITY_VALID;
    const auto start = std::chrono::steady_clock::now();
    for (uint64_t i = 0; i < count; ++i) {
        header.timestamp_ns = i;
        const auto status = fast ? as_bus_publish_fast(writer, header, data.data(), data.size())
                                 : as_bus_publish(bus, header, data.data(), data.size());
        if (status != ASBUS_OK) return 3;
    }
    const auto elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    ASBusTopicStats stats{};
    ASBusMemoryStats memory{};
    as_bus_stats(bus, ASBUS_HEAD, &stats);
    as_bus_memory_stats(bus, &memory);
    std::printf("mode=%s published=%llu payload_bytes=%zu readers=%u seconds=%.6f events_per_second=%.0f "
                "throughput_MiBps=%.1f retained_bytes=%llu peak_live_bytes=%llu\n",
                fast ? "fast" : "indexed", static_cast<unsigned long long>(stats.published),
                payload_bytes, readers, elapsed, static_cast<double>(count) / elapsed,
                static_cast<double>(count) * payload_bytes / elapsed / 1048576,
                static_cast<unsigned long long>(stats.retained_bytes),
                static_cast<unsigned long long>(memory.high_water_bytes));
    for (auto *subscriber : subscriptions) as_bus_unsubscribe(subscriber);
    as_bus_close_publisher(writer);
    as_bus_destroy(bus);
}
