#include "test_common.h"
#include "../Kernel/include/aerospatial_native.h"
#include <cmath>

int main() {
    ASCameraIntrinsics camera{1000, 1000, 960, 540, 1920, 1080};
    ASVector3 ray{}, point{};
    REQUIRE(as_camera_unproject(camera, 960, 540, &ray) == AS_OK);
    REQUIRE(std::abs(ray.x) < 1e-12 && std::abs(ray.y) < 1e-12);
    REQUIRE(std::abs(ray.z - 1) < 1e-12);
    // A camera rotated 180 deg about its X axis looks straight down in ENU.
    ASQuaternion downward{0, 1, 0, 0};
    REQUIRE(as_camera_ground_intersection(camera, 960, 540, {0, 0, 100}, downward,
                                          0, 2000, &point) == AS_OK);
    REQUIRE(std::abs(point.x) < 1e-10 && std::abs(point.y) < 1e-10);
    REQUIRE(std::abs(point.z) < 1e-10);
    REQUIRE(as_camera_ground_intersection(camera, 1460, 540, {0, 0, 100}, downward,
                                          0, 2000, &point) == AS_OK);
    REQUIRE(std::abs(point.x - 50) < 1e-9);
    REQUIRE(as_camera_ground_intersection(camera, 1460, 540, {0, 0, 100}, downward,
                                          0, 100, &point) == AS_INVALID_ARGUMENT);
    REQUIRE(as_camera_ground_intersection(camera, 960, 540, {0, 0, 100}, {1, 0, 0, 0},
                                          0, 2000, &point) == AS_INVALID_ARGUMENT);
    REQUIRE(as_camera_unproject(camera, -1, 1, &ray) == AS_INVALID_ARGUMENT);
    REQUIRE(as_camera_unproject(camera, 1920, 500, &ray) == AS_INVALID_ARGUMENT);
    REQUIRE(as_camera_unproject({0, 1000, 960, 540, 1920, 1080}, 960, 540, &ray) == AS_INVALID_ARGUMENT);
    REQUIRE(as_camera_ground_intersection(camera, 960, 540, {0, 0, NAN}, downward,
                                          0, 2000, &point) == AS_INVALID_ARGUMENT);
}
