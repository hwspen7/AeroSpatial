#include "aerospatial_native.h"
#include <cmath>

namespace {
bool normalized(ASQuaternion q, ASQuaternion *out) {
    if (!std::isfinite(q.w) || !std::isfinite(q.x) ||
        !std::isfinite(q.y) || !std::isfinite(q.z)) return false;
    const double norm = std::hypot(std::hypot(q.w, q.x), std::hypot(q.y, q.z));
    if (!std::isfinite(norm) || norm < 1e-12) return false;
    *out = {q.w / norm, q.x / norm, q.y / norm, q.z / norm};
    return true;
}
}

extern "C" ASStatus as_quaternion_inverse(ASQuaternion q, ASQuaternion *result) {
    if (!result) return AS_INVALID_ARGUMENT;
    ASQuaternion unit{};
    if (!normalized(q, &unit)) return AS_INVALID_ARGUMENT;
    *result = {unit.w, -unit.x, -unit.y, -unit.z};
    return AS_OK;
}

extern "C" ASStatus as_quaternion_multiply(ASQuaternion a, ASQuaternion b,
                                              ASQuaternion *result) {
    if (!result) return AS_INVALID_ARGUMENT;
    ASQuaternion x{}, y{};
    if (!normalized(a, &x) || !normalized(b, &y)) return AS_INVALID_ARGUMENT;
    const ASQuaternion q{
        x.w*y.w - x.x*y.x - x.y*y.y - x.z*y.z,
        x.w*y.x + x.x*y.w + x.y*y.z - x.z*y.y,
        x.w*y.y - x.x*y.z + x.y*y.w + x.z*y.x,
        x.w*y.z + x.x*y.y - x.y*y.x + x.z*y.w
    };
    return normalized(q, result) ? AS_OK : AS_INVALID_ARGUMENT;
}
