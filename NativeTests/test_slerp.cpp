#include "test_common.h"
#include "aerospatial_native.h"
#include <cmath>

int main() {
    ASQuaternion a{}, b{}, result{};
    REQUIRE(as_euler_to_quaternion(0, 0, 0, &a) == AS_OK);
    REQUIRE(as_euler_to_quaternion(90, 0, 0, &b) == AS_OK);
    REQUIRE(as_quaternion_slerp(a, b, 0.5, &result) == AS_OK);
    ASVector3 rotated{};
    REQUIRE(as_rotate_vector(result, {1,0,0}, &rotated) == AS_OK);
    REQUIRE(std::abs(rotated.x - std::sqrt(0.5)) < 1e-8);
    REQUIRE(std::abs(rotated.y - std::sqrt(0.5)) < 1e-8);
    REQUIRE(as_quaternion_slerp(a, {-b.w,-b.x,-b.y,-b.z}, 0.5, &result) == AS_OK);
    REQUIRE(as_rotate_vector(result, {1,0,0}, &rotated) == AS_OK);
    REQUIRE(std::abs(rotated.y - std::sqrt(0.5)) < 1e-8);
    REQUIRE(as_quaternion_slerp(a, b, -0.1, &result) == AS_INVALID_ARGUMENT);
    REQUIRE(as_quaternion_slerp(a, {0,0,0,0}, 0.5, &result) == AS_INVALID_ARGUMENT);
    return 0;
}
