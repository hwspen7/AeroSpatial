#include "test_common.h"
#include "../Kernel/include/aerospatial_bus.h"
#include <atomic>
#include <cstdint>
#include <thread>

static void write_many(ASBusPublisher *writer, uint32_t stream,
                       std::atomic<uint64_t> &accepted, std::atomic<uint64_t> &denied) {
    uint8_t data[1024]{};
    for (uint64_t i = 0; i < 2500; ++i) {
        ASBusHeader header{};
        header.stream_id = stream;
        header.clock_domain = 1;
        header.timestamp_ns = 0;  // Multiple producers can share a monotonic timestamp.
        header.quality_flags = ASBUS_QUALITY_VALID;
        const auto status = as_bus_publish_fast(writer, header, data, sizeof(data));
        if (status == ASBUS_OK) ++accepted;
        else {
            REQUIRE(status == ASBUS_MEMORY_BUDGET);
            ++denied;
        }
    }
}

int main() {
    ASBusConfig config{3, 4};
    auto *bus = as_bus_create(&config);
    REQUIRE(bus);
    REQUIRE(as_bus_set_payload_budget(bus, 32 * 1024) == ASBUS_OK);
    REQUIRE(as_bus_add_topic(bus, {ASBUS_HEAD, 64, 1024, ASBUS_OVERWRITE_OLDEST}) == ASBUS_OK);
    REQUIRE(as_bus_add_topic(bus, {ASBUS_TELEMETRY, 64, 1024, ASBUS_OVERWRITE_OLDEST}) == ASBUS_OK);
    auto *a = as_bus_open_publisher(bus, ASBUS_HEAD);
    auto *b = as_bus_open_publisher(bus, ASBUS_TELEMETRY);
    REQUIRE(a && b);
    std::atomic<uint64_t> accepted{0}, denied{0};
    std::thread producerA(write_many, a, ASBUS_HEAD, std::ref(accepted), std::ref(denied));
    std::thread producerB(write_many, b, ASBUS_TELEMETRY, std::ref(accepted), std::ref(denied));
    for (int i = 0; i < 1000; ++i) {
        ASBusMemoryStats memory{};
        REQUIRE(as_bus_memory_stats(bus, &memory) == ASBUS_OK);
        REQUIRE(memory.live_bytes <= memory.limit_bytes);
        REQUIRE(memory.high_water_bytes <= memory.limit_bytes);
    }
    producerA.join();
    producerB.join();
    REQUIRE(accepted > 0 && denied > 0 && accepted + denied == 5000);
    ASBusMemoryStats memory{};
    REQUIRE(as_bus_memory_stats(bus, &memory) == ASBUS_OK);
    REQUIRE(memory.live_bytes <= 32 * 1024);
    as_bus_close_publisher(a);
    as_bus_close_publisher(b);
    as_bus_destroy(bus);
}
