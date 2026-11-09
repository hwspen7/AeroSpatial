#include "test_common.h"
#include "aerospatial_native.h"
#include <cmath>

int main() {
    ASVector3 ecef{}, enu{};
    REQUIRE(as_wgs84_ecef({0, 0, 0}, &ecef) == AS_OK);
    REQUIRE(std::abs(ecef.x - 6378137) < 1e-5);
    REQUIRE(std::abs(ecef.y) < 1e-5);
    REQUIRE(std::abs(ecef.z) < 1e-5);
    REQUIRE(as_wgs84_enu({0, 0, 0}, {0, 0, 100}, &enu) == AS_OK);
    REQUIRE(std::abs(enu.z - 100) < 1e-6);
    REQUIRE(std::abs(enu.x) < 1e-6);
    REQUIRE(as_wgs84_enu({0, 179.999, 0}, {0, -179.999, 0}, &enu) == AS_OK);
    REQUIRE(enu.x > 220 && enu.x < 225);
    REQUIRE(as_wgs84_enu({90, 0, 0}, {90, 1, 0}, &enu) == AS_OK);
    REQUIRE(std::abs(enu.x) < 1e-5);
    REQUIRE(as_wgs84_ecef({91, 0, 0}, &ecef) == AS_INVALID_ARGUMENT);
    REQUIRE(as_wgs84_enu({0, 0, 0}, {0, 0, NAN}, &enu) == AS_INVALID_ARGUMENT);
    REQUIRE(as_wgs84_ecef({0, 0, 0}, nullptr) == AS_INVALID_ARGUMENT);
    return 0;
}
