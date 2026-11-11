#include "aerospatial_native.h"
#include "test_common.h"
#include <cmath>

int main() {
    ASFilterState filter{};
    double output = 0;
    REQUIRE(as_filter_update(&filter, 1, 10, 0.5, 0.1, 1, 30, &output) == AS_OK);
    REQUIRE(output == 10);
    REQUIRE(as_filter_update(&filter, 1.1, 12, 0.5, 0.1, 1, 30, &output) == AS_OK);
    REQUIRE(std::abs(output - 11) < 1e-10);
    const double saved = filter.position;
    REQUIRE(as_filter_update(&filter, 1.1, 99, 0.5, 0.1, 1, 30, &output) == AS_OUT_OF_ORDER);
    REQUIRE(as_filter_update(&filter, 1.2, 999, 0.5, 0.1, 1, 30, &output) == AS_OUTLIER_REJECTED);
    REQUIRE(filter.position == saved);
    REQUIRE(as_filter_update(&filter, 3, 6, 0.5, 0.1, 1, 30, &output) == AS_RESET_AFTER_GAP);
    REQUIRE(output == 6 && filter.velocity == 0);
    REQUIRE(as_filter_update(&filter, 3.1, 7, -1, 0.1, 1, 30, &output) == AS_INVALID_ARGUMENT);
    as_filter_reset(&filter);
    REQUIRE(filter.initialized == 0);
}
