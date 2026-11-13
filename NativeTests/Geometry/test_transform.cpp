#include "aerospatial_native.h"
#include "test_common.h"
#include <cmath>

int main() {
    ASQuaternion yaw{}, inverse{}, identity{};
    REQUIRE(as_euler_to_quaternion(70, 0, 0, &yaw) == AS_OK);
    REQUIRE(as_quaternion_inverse(yaw, &inverse) == AS_OK);
    REQUIRE(as_quaternion_multiply(yaw, inverse, &identity) == AS_OK);
    REQUIRE(std::abs(identity.w - 1) < 1e-9);
    REQUIRE(std::abs(identity.x) < 1e-9);
    REQUIRE(std::abs(identity.y) < 1e-9);
    REQUIRE(std::abs(identity.z) < 1e-9);
    REQUIRE(as_quaternion_multiply({0,0,0,0}, yaw, &identity) == AS_INVALID_ARGUMENT);
    REQUIRE(as_quaternion_inverse(yaw, nullptr) == AS_INVALID_ARGUMENT);
    return 0;
}
