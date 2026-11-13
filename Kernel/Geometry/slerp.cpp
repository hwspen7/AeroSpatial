#include "aerospatial_native.h"
#include <algorithm>
#include <cmath>

namespace {
bool normalize(ASQuaternion input, ASQuaternion *out) {
    if (!std::isfinite(input.w) || !std::isfinite(input.x) ||
        !std::isfinite(input.y) || !std::isfinite(input.z)) return false;
    const double norm = std::hypot(std::hypot(input.w, input.x), std::hypot(input.y, input.z));
    if (!std::isfinite(norm) || norm <= 1e-12) return false;
    *out = {input.w/norm, input.x/norm, input.y/norm, input.z/norm};
    return true;
}
}

extern "C" ASStatus as_quaternion_slerp(ASQuaternion a, ASQuaternion b, double t,
                                           ASQuaternion *result) {
    if (!result || !std::isfinite(t) || t < 0.0 || t > 1.0) return AS_INVALID_ARGUMENT;
    ASQuaternion start{}, end{};
    if (!normalize(a, &start) || !normalize(b, &end)) return AS_INVALID_ARGUMENT;
    double dot = start.w * end.w + start.x * end.x + start.y * end.y + start.z * end.z;
    if (dot < 0) {
        end = {-end.w, -end.x, -end.y, -end.z};
        dot = -dot;
    }
    dot = std::clamp(dot, -1.0, 1.0);
    double a_weight = 1.0 - t, b_weight = t;
    if (dot < 0.9995) {
        const double angle = std::acos(dot);
        const double inverse = 1.0 / std::sin(angle);
        a_weight = std::sin((1.0 - t) * angle) * inverse;
        b_weight = std::sin(t * angle) * inverse;
    }
    ASQuaternion interpolated{a_weight*start.w+b_weight*end.w,
                              a_weight*start.x+b_weight*end.x,
                              a_weight*start.y+b_weight*end.y,
                              a_weight*start.z+b_weight*end.z};
    return normalize(interpolated, result) ? AS_OK : AS_INVALID_ARGUMENT;
}
