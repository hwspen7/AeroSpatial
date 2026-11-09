#include "aerospatial_native.h"
#include "test_common.h"
#include <cmath>
#include <limits>

int main() {
    ASQuaternion orientation{};
    ASVector3 rotated{};
    REQUIRE(as_euler_to_quaternion(90, 0, 0, &orientation) == AS_OK);
    REQUIRE(as_rotate_vector(orientation, {1, 0, 0}, &rotated) == AS_OK);
    REQUIRE(std::abs(rotated.x) < 1e-10 && std::abs(rotated.y - 1) < 1e-10);
    REQUIRE(as_rotate_vector({0, 0, 0, 0}, {1, 0, 0}, &rotated) == AS_INVALID_ARGUMENT);
    REQUIRE(as_euler_to_quaternion(std::numeric_limits<double>::quiet_NaN(), 0, 0,
                                  &orientation) == AS_INVALID_ARGUMENT);
    double pan = 0;
    REQUIRE(as_stereo_pan(-90, &pan) == AS_OK && std::abs(pan + 1) < 1e-10);
    REQUIRE(as_stereo_pan(90, &pan) == AS_OK && std::abs(pan - 1) < 1e-10);
    REQUIRE(as_stereo_pan(0, nullptr) == AS_INVALID_ARGUMENT);
}
