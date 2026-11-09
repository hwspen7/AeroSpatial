#include "aerospatial_native.h"
#include <cmath>

namespace {
constexpr double kA = 6378137.0;
constexpr double kE2 = 6.6943799901413165e-3;
constexpr double kRad = 3.14159265358979323846 / 180.0;
bool valid(ASGeodetic3 point) {
    return std::isfinite(point.latitude) && std::isfinite(point.longitude) &&
           std::isfinite(point.altitude) && std::abs(point.latitude) <= 90.0 &&
           std::abs(point.longitude) <= 180.0 && std::abs(point.altitude) <= 10000000.0;
}
}

extern "C" ASStatus as_wgs84_ecef(ASGeodetic3 point, ASVector3 *result) {
    if (!result || !valid(point)) return AS_INVALID_ARGUMENT;
    const double latitude = point.latitude * kRad;
    const double longitude = point.longitude * kRad;
    const double sin_lat = std::sin(latitude);
    const double cos_lat = std::cos(latitude);
    const double prime_vertical = kA / std::sqrt(1.0 - kE2 * sin_lat * sin_lat);
    *result = {(prime_vertical + point.altitude) * cos_lat * std::cos(longitude),
               (prime_vertical + point.altitude) * cos_lat * std::sin(longitude),
               (prime_vertical * (1.0 - kE2) + point.altitude) * sin_lat};
    return AS_OK;
}

extern "C" ASStatus as_wgs84_enu(ASGeodetic3 origin, ASGeodetic3 target, ASVector3 *result) {
    if (!result) return AS_INVALID_ARGUMENT;
    ASVector3 start{};
    ASVector3 end{};
    if (as_wgs84_ecef(origin, &start) != AS_OK ||
        as_wgs84_ecef(target, &end) != AS_OK) return AS_INVALID_ARGUMENT;
    const double latitude = origin.latitude * kRad;
    const double longitude = origin.longitude * kRad;
    const double s_lat = std::sin(latitude), c_lat = std::cos(latitude);
    const double s_lon = std::sin(longitude), c_lon = std::cos(longitude);
    const double dx = end.x - start.x, dy = end.y - start.y, dz = end.z - start.z;
    *result = {-s_lon * dx + c_lon * dy,
               -s_lat * c_lon * dx - s_lat * s_lon * dy + c_lat * dz,
               c_lat * c_lon * dx + c_lat * s_lon * dy + s_lat * dz};
    return AS_OK;
}
