#include "aerospatial_native.h"
#include <cmath>

namespace {
bool valid(ASGeodetic3 p) {
    return std::isfinite(p.latitude) && std::isfinite(p.longitude) &&
           std::isfinite(p.altitude) && std::abs(p.latitude) <= 90 &&
           std::abs(p.longitude) <= 180 && std::abs(p.altitude) <= 1e7;
}
}

extern "C" ASStatus as_wgs84_ecef_batch(const ASGeodetic3 *points, size_t count,
                                           ASVector3 *result) {
    if (count == 0) return AS_OK;
    if (!points || !result) return AS_INVALID_ARGUMENT;
    for (size_t i = 0; i < count; ++i) {
        if (!valid(points[i])) return AS_INVALID_ARGUMENT;
    }
    for (size_t i = 0; i < count; ++i) {
        if (as_wgs84_ecef(points[i], result + i) != AS_OK) return AS_INVALID_ARGUMENT;
    }
    return AS_OK;
}

extern "C" ASStatus as_lowpass_batch(const double *measurements, size_t count,
                                        double alpha, double initial, double *result) {
    if (!std::isfinite(alpha) || alpha < 0 || alpha > 1 || !std::isfinite(initial))
        return AS_INVALID_ARGUMENT;
    if (count == 0) return AS_OK;
    if (!measurements || !result) return AS_INVALID_ARGUMENT;
    for (size_t i = 0; i < count; ++i) {
        if (!std::isfinite(measurements[i])) return AS_INVALID_ARGUMENT;
    }
    double state = initial;
    for (size_t i = 0; i < count; ++i) {
        state += alpha * (measurements[i] - state);
        result[i] = state;
    }
    return AS_OK;
}
