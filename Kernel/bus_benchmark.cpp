#include "include/aerospatial_bus.h"
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <cstdlib>

int main(int argc, char **argv) {
    const uint64_t count = argc > 1 ? std::strtoull(argv[1], nullptr, 10) : 500000;
    if (!count || count > 20000000) return 2;
    ASBusConfig config{4, 4};
    ASBus *bus = as_bus_create(&config);
    if (!bus || as_bus_add_topic(bus, {ASBUS_HEAD, 1024, 32, ASBUS_OVERWRITE_OLDEST}) != ASBUS_OK) return 2;
    ASBusHeader hdr{};
    hdr.stream_id = ASBUS_HEAD;
    hdr.clock_domain = 1;
    hdr.quality_flags = ASBUS_QUALITY_VALID;
    const uint64_t value = 12345;
    const auto start = std::chrono::steady_clock::now();
    for (uint64_t i = 0; i < count; ++i) {
        hdr.timestamp_ns = i;
        if (as_bus_publish(bus, hdr, &value, sizeof(value)) != ASBUS_OK) return 3;
    }
    const auto elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    ASBusTopicStats stats{};
    as_bus_stats(bus, ASBUS_HEAD, &stats);
    std::printf("published=%llu elapsed_seconds=%.6f events_per_second=%.0f overwritten=%llu\n",
                static_cast<unsigned long long>(stats.published), elapsed,
                static_cast<double>(count) / elapsed,
                static_cast<unsigned long long>(stats.overwritten));
    as_bus_destroy(bus);
}
