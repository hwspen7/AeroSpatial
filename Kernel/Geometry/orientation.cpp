#include "aerospatial_native.h"
#include <cmath>

extern "C" ASStatus as_euler_to_quaternion(double yaw, double pitch, double roll,
                                               ASQuaternion *result) {
    if (!result || !std::isfinite(yaw) || !std::isfinite(pitch) || !std::isfinite(roll))
        return AS_INVALID_ARGUMENT;
    constexpr double kHalfRad = 3.14159265358979323846 / 360.0;
    const double cy = std::cos(yaw * kHalfRad), sy = std::sin(yaw * kHalfRad);
    const double cp = std::cos(pitch * kHalfRad), sp = std::sin(pitch * kHalfRad);
    const double cr = std::cos(roll * kHalfRad), sr = std::sin(roll * kHalfRad);
    *result = {cr*cp*cy + sr*sp*sy, sr*cp*cy - cr*sp*sy,
               cr*sp*cy + sr*cp*sy, cr*cp*sy - sr*sp*cy};
    return AS_OK;
}

extern "C" ASStatus as_rotate_vector(ASQuaternion rotation, ASVector3 input,
                                        ASVector3 *result) {
    if (!result || !std::isfinite(rotation.w) || !std::isfinite(rotation.x) ||
        !std::isfinite(rotation.y) || !std::isfinite(rotation.z) ||
        !std::isfinite(input.x) || !std::isfinite(input.y) || !std::isfinite(input.z))
        return AS_INVALID_ARGUMENT;
    const double norm2 = rotation.w*rotation.w + rotation.x*rotation.x +
                         rotation.y*rotation.y + rotation.z*rotation.z;
    if (!std::isfinite(norm2) || norm2 < 1e-12) return AS_INVALID_ARGUMENT;
    const double inv = 1.0 / std::sqrt(norm2);
    const double w = rotation.w*inv, x = rotation.x*inv, y = rotation.y*inv, z = rotation.z*inv;
    const double xx = x*x, yy = y*y, zz = z*z;
    *result = {
        (1 - 2*(yy + zz))*input.x + 2*(x*y - w*z)*input.y + 2*(x*z + w*y)*input.z,
        2*(x*y + w*z)*input.x + (1 - 2*(xx + zz))*input.y + 2*(y*z - w*x)*input.z,
        2*(x*z - w*y)*input.x + 2*(y*z + w*x)*input.y + (1 - 2*(xx + yy))*input.z
    };
    return AS_OK;
}
