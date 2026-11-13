#include "test_common.h"
#include "aerospatial_runtime.h"
#include <thread>
#include <vector>
int main() {
    REQUIRE(as_clock_quality_create(0, 100, 100) == nullptr);
    auto *q = as_clock_quality_create(1000, 100, 60);
    REQUIRE(q);
    ASClockReport report{};
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_AIRPODS, 100, 10000, 10100, 20, &report) ==
            AS_CLOCK_ACCEPTED);
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_IPHONE, 500, 10500, 10600, 20, &report) ==
            AS_CLOCK_ACCEPTED);
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_AIRCRAFT, 900, 11000, 11100, 20, &report) ==
            AS_CLOCK_ACCEPTED);
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_AIRPODS, 90, 10100, 10200, 20, &report) ==
            AS_CLOCK_REGRESSION);
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_AIRPODS, 200, 10100, 10200, 150, &report) ==
            AS_CLOCK_UNCERTAIN);
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_AIRPODS, 200, 12000, 12050, 10, &report) ==
            AS_CLOCK_JUMP);
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_AIRPODS, 200, 10100, 11001, 10, &report) ==
            AS_CLOCK_STALE);
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_AIRPODS, 200, 10100, 10200, 10, &report) ==
            AS_CLOCK_ACCEPTED);
    REQUIRE(report.accepted == 2 && report.rejected == 4);
    REQUIRE(report.last_age_ns == 100 && report.last_uncertainty_ns == 10);
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_AIRPODS, 300, 10300, 10290, 10, &report) ==
            AS_CLOCK_STALE);
    REQUIRE(!as_clock_quality_reset(q, 0));
    REQUIRE(as_clock_quality_reset(q, AS_CLOCK_AIRPODS));
    REQUIRE(as_clock_quality_observe(q, AS_CLOCK_AIRPODS, 1, 20000, 20020, 2, &report) ==
            AS_CLOCK_ACCEPTED);
    REQUIRE(report.accepted == 3 && report.has_anchor);
    REQUIRE(as_clock_quality_observe(q, 4, 1, 1, 1, 0, &report) == AS_CLOCK_INVALID);
    as_clock_quality_destroy(q);
}
