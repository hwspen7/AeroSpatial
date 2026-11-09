#include "test_common.h"
#include "../Kernel/include/aerospatial_bus.h"
#include <cstdint>
#include <cstring>

static ASBusHeader header(uint32_t stream, uint64_t ns) {
    ASBusHeader h{};
    h.stream_id = stream;
    h.timestamp_ns = ns;
    h.clock_domain = 1;
    h.quality_flags = ASBUS_QUALITY_VALID;
    return h;
}

static ASBus *bus(uint32_t cap, uint32_t policy) {
    ASBusConfig config{5, 4};
    ASBus *instance = as_bus_create(&config);
    REQUIRE(instance);
    REQUIRE(as_bus_add_topic(instance, {ASBUS_HEAD, cap, 32, policy}) == ASBUS_OK);
    return instance;
}

static void fanout_and_gaps() {
    auto *instance = bus(3, ASBUS_OVERWRITE_OLDEST);
    auto *a = as_bus_subscribe(instance, ASBUS_HEAD, 0);
    auto *b = as_bus_subscribe(instance, ASBUS_HEAD, 1);
    REQUIRE(a && b);
    for (int i = 1; i <= 5; ++i) {
        REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, i), &i, sizeof(i)) == ASBUS_OK);
    }
    int payload = 0;
    size_t length = 0;
    ASBusHeader result{};
    uint64_t missed = 0;
    REQUIRE(as_bus_poll(a, &payload, sizeof(payload), &result, &length, &missed) == ASBUS_OK);
    REQUIRE(result.sequence == 3 && payload == 3 && missed == 2);
    REQUIRE(as_bus_poll(b, &payload, sizeof(payload), &result, &length, &missed) == ASBUS_OK);
    REQUIRE(result.sequence == 3 && missed == 2);
    REQUIRE(as_bus_poll(a, &payload, 1, &result, &length, &missed) == ASBUS_BUFFER_TOO_SMALL);
    REQUIRE(length == 4);
    REQUIRE(as_bus_poll(a, &payload, sizeof(payload), &result, &length, &missed) == ASBUS_OK);
    REQUIRE(result.sequence == 4 && missed == 0);
    ASBusTopicStats stats{};
    REQUIRE(as_bus_stats(instance, ASBUS_HEAD, &stats) == ASBUS_OK);
    REQUIRE(stats.published == 5 && stats.overwritten == 2 && stats.retained_events == 3);
    as_bus_unsubscribe(a);
    as_bus_unsubscribe(b);
    as_bus_destroy(instance);
}

static void backpressure_recovery() {
    auto *instance = bus(2, ASBUS_REJECT_NEWEST);
    auto *reader = as_bus_subscribe(instance, ASBUS_HEAD, 0);
    int value = 42;
    REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, 2), &value, 4) == ASBUS_OK);
    REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, 3), &value, 4) == ASBUS_OK);
    REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, 4), &value, 4) == ASBUS_BACKPRESSURE);
    ASBusHeader out{};
    size_t length = 0;
    uint64_t missed = 0;
    REQUIRE(as_bus_poll(reader, &value, 4, &out, &length, &missed) == ASBUS_OK);
    REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, 5), &value, 4) == ASBUS_OK);
    REQUIRE(as_bus_poll(reader, &value, 4, &out, &length, &missed) == ASBUS_OK);
    REQUIRE(out.sequence == 2 && missed == 0);
    REQUIRE(as_bus_poll(reader, &value, 4, &out, &length, &missed) == ASBUS_OK);
    REQUIRE(out.sequence == 3);
    REQUIRE(as_bus_poll(reader, &value, 4, &out, &length, &missed) == ASBUS_EMPTY);
    as_bus_unsubscribe(reader);
    as_bus_destroy(instance);
}

static void lease_and_validation() {
    auto *instance = bus(1, ASBUS_OVERWRITE_OLDEST);
    auto *reader = as_bus_subscribe(instance, ASBUS_HEAD, 0);
    const char first[] = "old";
    REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, 100), first, 3) == ASBUS_OK);
    ASBusLease *lease = nullptr;
    uint64_t missed = 0;
    REQUIRE(as_bus_acquire(reader, &lease, &missed) == ASBUS_OK);
    REQUIRE(as_bus_acquire(reader, &lease, &missed) == ASBUS_BUSY);
    const char second[] = "new";
    REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, 101), second, 3) == ASBUS_OK);
    ASBusHeader metadata{};
    size_t size = 0;
    REQUIRE(std::memcmp(as_bus_lease_data(lease, &size, &metadata), "old", 3) == 0);
    REQUIRE(size == 3 && metadata.sequence == 1);
    as_bus_release(lease);
    REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, 99), second, 3) == ASBUS_TIME_REGRESSION);
    auto invalid = header(ASBUS_HEAD, 102);
    invalid.quality_flags = 0;
    REQUIRE(as_bus_publish(instance, invalid, second, 3) == ASBUS_INVALID);
    REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, 102), second, 33) == ASBUS_TOO_LARGE);
    REQUIRE(as_bus_publish(instance, header(ASBUS_HEAD, 102), nullptr, 3) == ASBUS_INVALID);
    ASBusTopicStats stats{};
    REQUIRE(as_bus_stats(instance, ASBUS_HEAD, &stats) == ASBUS_OK);
    REQUIRE(stats.published == 2 && stats.overwritten == 1 && stats.invalid == 3);
    as_bus_unsubscribe(reader);
    as_bus_destroy(instance);
}

static void lifecycle_and_limits() {
    ASBusConfig invalid{0, 1};
    REQUIRE(as_bus_create(&invalid) == nullptr);
    auto *instance = bus(1, ASBUS_OVERWRITE_OLDEST);
    REQUIRE(as_bus_add_topic(instance, {ASBUS_HEAD, 2, 4, ASBUS_OVERWRITE_OLDEST}) == ASBUS_INVALID);
    REQUIRE(as_bus_add_topic(instance, {ASBUS_TELEMETRY, 4096, 8*1024*1024, ASBUS_REJECT_NEWEST}) == ASBUS_INVALID);
    auto *reader = as_bus_subscribe(instance, ASBUS_HEAD, 1);
    REQUIRE(reader);
    as_bus_destroy(instance);
    ASBusHeader out{};
    int value = 0;
    size_t length = 0;
    uint64_t missed = 0;
    REQUIRE(as_bus_poll(reader, &value, sizeof(value), &out, &length, &missed) == ASBUS_EMPTY);
    as_bus_unsubscribe(reader);
}

int main() {
    fanout_and_gaps();
    backpressure_recovery();
    lease_and_validation();
    lifecycle_and_limits();
    return 0;
}
