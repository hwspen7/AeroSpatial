#include "test_common.h"
#include "../Kernel/include/aerospatial_bus.h"
#include <cstdint>

extern "C" void as_bus_test_fail_subscribe_at(int point);

int main() {
    ASBusConfig config{1, 2};
    auto *bus = as_bus_create(&config);
    REQUIRE(bus);
    REQUIRE(as_bus_add_topic(bus, {ASBUS_HEAD, 2, 16, ASBUS_OVERWRITE_OLDEST}) == ASBUS_OK);
    for (int point = 1; point <= 3; ++point) {
        as_bus_test_fail_subscribe_at(point);
        REQUIRE(as_bus_subscribe(bus, ASBUS_HEAD, 0) == nullptr);
        ASBusTopicStats stats{};
        REQUIRE(as_bus_stats(bus, ASBUS_HEAD, &stats) == ASBUS_OK);
        REQUIRE(stats.active_subscribers == 0);
        auto *healthy = as_bus_subscribe(bus, ASBUS_HEAD, 0);
        REQUIRE(healthy);
        as_bus_unsubscribe(healthy);
    }
    auto *a = as_bus_subscribe(bus, ASBUS_HEAD, 0);
    auto *b = as_bus_subscribe(bus, ASBUS_HEAD, 0);
    REQUIRE(a && b);
    REQUIRE(as_bus_subscribe(bus, ASBUS_HEAD, 0) == nullptr);
    as_bus_unsubscribe(a);
    as_bus_unsubscribe(b);
    as_bus_destroy(bus);
}
