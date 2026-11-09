#include "aerospatial_native.h"
#include "test_common.h"
#include <cmath>

int main() {
    double distance = 0, bearing = 0;
    REQUIRE(as_geodesic({0, 0}, {0, 0.001}, &distance, &bearing) == AS_OK);
    REQUIRE(std::abs(distance - 111.195) < .3);
    REQUIRE(std::abs(bearing - 90) < 1e-7);
    REQUIRE(as_geodesic({0, 179.999}, {0, -179.999}, &distance, &bearing) == AS_OK);
    REQUIRE(distance < 300 && bearing > 89 && bearing < 91);
    ASVector3 result{};
    REQUIRE(as_local_enu({0, 0}, {0.001, 0}, 8, &result) == AS_OK);
    REQUIRE(std::abs(result.y - 111.195) < .3 && result.z == 8);
    REQUIRE(as_local_enu({0, 0}, {60, 60}, 0, &result) == AS_INVALID_ARGUMENT);
    REQUIRE(as_geodesic({99, 0}, {0, 0}, &distance, &bearing) == AS_INVALID_ARGUMENT);
    REQUIRE(as_geodesic({0, 0}, {0, 0}, nullptr, &bearing) == AS_INVALID_ARGUMENT);
}
