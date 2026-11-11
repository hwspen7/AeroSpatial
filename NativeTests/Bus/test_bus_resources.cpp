#include "test_common.h"
#include "../Kernel/include/aerospatial_bus.h"
#include <cstdint>

static ASBusHeader header(uint64_t time) {
    ASBusHeader h{};
    h.stream_id = ASBUS_HEAD;
    h.clock_domain = 1;
    h.quality_flags = ASBUS_QUALITY_VALID;
    h.timestamp_ns = time;
    return h;
}

static void budget_and_lease_reclamation() {
    ASBusConfig config{2, 3};
    ASBus *bus = as_bus_create(&config);
    REQUIRE(bus);
    REQUIRE(as_bus_set_payload_budget(bus, 12) == ASBUS_OK);
    REQUIRE(as_bus_add_topic(bus, {ASBUS_HEAD, 2, 8, ASBUS_OVERWRITE_OLDEST}) == ASBUS_OK);
    REQUIRE(as_bus_set_payload_budget(bus, 100) == ASBUS_BUSY);
    ASBusPublisher *writer = as_bus_open_publisher(bus, ASBUS_HEAD);
    ASBusSubscription *reader = as_bus_subscribe(bus, ASBUS_HEAD, 0);
    REQUIRE(writer && reader);
    uint32_t data = 7;
    REQUIRE(as_bus_publish_fast(writer, header(1), &data, 4) == ASBUS_OK);
    REQUIRE(as_bus_publish_fast(writer, header(2), &data, 4) == ASBUS_OK);
    ASBusLease *lease = nullptr;
    uint64_t missed = 0;
    REQUIRE(as_bus_acquire(reader, &lease, &missed) == ASBUS_OK);
    REQUIRE(as_bus_publish_fast(writer, header(3), &data, 4) == ASBUS_OK);
    ASBusMemoryStats memory{};
    REQUIRE(as_bus_memory_stats(bus, &memory) == ASBUS_OK);
    REQUIRE(memory.limit_bytes == 12 && memory.live_bytes == 12);
    REQUIRE(as_bus_publish_fast(writer, header(4), &data, 4) == ASBUS_MEMORY_BUDGET);
    ASBusTopicStats stats{};
    REQUIRE(as_bus_stats(bus, ASBUS_HEAD, &stats) == ASBUS_OK);
    REQUIRE(stats.budget_rejected == 1 && stats.published == 3);
    ASBusHeader retained{};
    size_t length = 0;
    REQUIRE(as_bus_lease_data(lease, &length, &retained));
    REQUIRE(retained.sequence == 1 && length == 4);
    as_bus_release(lease);
    REQUIRE(as_bus_memory_stats(bus, &memory) == ASBUS_OK);
    REQUIRE(memory.live_bytes == 8);
    REQUIRE(as_bus_publish_fast(writer, header(4), &data, 4) == ASBUS_OK);
    REQUIRE(as_bus_memory_stats(bus, &memory) == ASBUS_OK);
    REQUIRE(memory.live_bytes == 8 && memory.high_water_bytes == 12);
    as_bus_unsubscribe(reader);
    as_bus_close_publisher(writer);
    as_bus_destroy(bus);
}

static void lifetime_and_closed_status() {
    ASBusConfig config{2, 2};
    auto *bus = as_bus_create(&config);
    REQUIRE(bus);
    REQUIRE(as_bus_add_topic(bus, {ASBUS_HEAD, 3, 8, ASBUS_REJECT_NEWEST}) == ASBUS_OK);
    auto *writer = as_bus_open_publisher(bus, ASBUS_HEAD);
    auto *reader = as_bus_subscribe(bus, ASBUS_HEAD, 0);
    REQUIRE(writer && reader);
    uint64_t value = 99;
    REQUIRE(as_bus_publish_fast(writer, header(10), &value, 8) == ASBUS_OK);
    as_bus_destroy(bus);
    REQUIRE(as_bus_publish_fast(writer, header(11), &value, 8) == ASBUS_CLOSED);
    ASBusHeader received{};
    size_t bytes = 0;
    uint64_t missed = 0;
    REQUIRE(as_bus_poll(reader, &value, 8, &received, &bytes, &missed) == ASBUS_OK);
    REQUIRE(received.sequence == 1 && bytes == 8 && value == 99);
    REQUIRE(as_bus_poll(reader, &value, 8, &received, &bytes, &missed) == ASBUS_CLOSED);
    as_bus_unsubscribe(reader);
    as_bus_close_publisher(writer);
}

static void invalid_configuration() {
    ASBusConfig config{2, 2};
    auto *bus = as_bus_create(&config);
    REQUIRE(bus);
    REQUIRE(as_bus_set_payload_budget(bus, 0) == ASBUS_INVALID);
    REQUIRE(as_bus_set_payload_budget(bus, (1ull << 34) + 1) == ASBUS_INVALID);
    REQUIRE(as_bus_set_payload_budget(bus, 8) == ASBUS_OK);
    REQUIRE(as_bus_add_topic(bus, {ASBUS_HEAD, 2, 8, ASBUS_OVERWRITE_OLDEST}) == ASBUS_OK);
    auto *writer = as_bus_open_publisher(bus, ASBUS_HEAD);
    REQUIRE(writer);
    uint64_t value = 0;
    REQUIRE(as_bus_publish_fast(writer, header(1), &value, 8) == ASBUS_OK);
    REQUIRE(as_bus_publish_fast(writer, header(2), &value, 8) == ASBUS_MEMORY_BUDGET);
    // A memory-budget failure does not consume the next sequence number.
    auto *reader = as_bus_subscribe(bus, ASBUS_HEAD, 0);
    REQUIRE(reader);
    ASBusHeader out{};
    size_t size = 0;
    uint64_t missed = 0;
    REQUIRE(as_bus_poll(reader, &value, 8, &out, &size, &missed) == ASBUS_OK);
    REQUIRE(out.sequence == 1);
    as_bus_unsubscribe(reader);
    as_bus_close_publisher(writer);
    as_bus_destroy(bus);
}

int main() {
    budget_and_lease_reclamation();
    lifetime_and_closed_status();
    invalid_configuration();
}
