#include "include/aerospatial_native.h"
#include <cmath>

namespace {
bool finite3(ASVector3 value) {
    return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z);
}
}  // namespace

extern "C" ASStatus as_camera_unproject(ASCameraIntrinsics camera, double pixel_x,
                                          double pixel_y, ASVector3 *unit_ray) {
    if (!unit_ray || !camera.width || !camera.height ||
        !std::isfinite(camera.fx) || !std::isfinite(camera.fy) ||
        !std::isfinite(camera.cx) || !std::isfinite(camera.cy) ||
        camera.fx <= 0 || camera.fy <= 0 || !std::isfinite(pixel_x) ||
        !std::isfinite(pixel_y) || pixel_x < 0 || pixel_y < 0 ||
        pixel_x >= camera.width || pixel_y >= camera.height) return AS_INVALID_ARGUMENT;
    const double x = (pixel_x - camera.cx) / camera.fx;
    const double y = (pixel_y - camera.cy) / camera.fy;
    const double length = std::hypot(std::hypot(x, y), 1.0);
    if (!std::isfinite(length) || length <= 0) return AS_INVALID_ARGUMENT;
    *unit_ray = {x / length, y / length, 1.0 / length};
    return AS_OK;
}

extern "C" ASStatus as_camera_ground_intersection(ASCameraIntrinsics camera, double pixel_x,
                                                    double pixel_y, ASVector3 camera_enu,
                                                    ASQuaternion camera_to_enu, double plane_up_m,
                                                    double max_distance_m, ASVector3 *result) {
    if (!result || !finite3(camera_enu) || !std::isfinite(plane_up_m) ||
        !std::isfinite(max_distance_m) || max_distance_m <= 0 || max_distance_m > 50000) {
        return AS_INVALID_ARGUMENT;
    }
    ASVector3 camera_ray{}, direction{};
    if (as_camera_unproject(camera, pixel_x, pixel_y, &camera_ray) != AS_OK ||
        as_rotate_vector(camera_to_enu, camera_ray, &direction) != AS_OK ||
        std::abs(direction.z) < 1e-8) return AS_INVALID_ARGUMENT;
    const double range = (plane_up_m - camera_enu.z) / direction.z;
    if (!std::isfinite(range) || range <= 0 || range > max_distance_m) return AS_INVALID_ARGUMENT;
    const ASVector3 point{camera_enu.x + range * direction.x,
                          camera_enu.y + range * direction.y, plane_up_m};
    if (!finite3(point)) return AS_INVALID_ARGUMENT;
    *result = point;
    return AS_OK;
}
