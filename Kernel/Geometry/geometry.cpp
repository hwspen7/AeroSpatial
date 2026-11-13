#include "aerospatial_native.h"
#include <algorithm>
#include <cmath>

namespace {
constexpr double kEarthRadiusMeters = 6371000.0;
constexpr double kRadiansPerDegree = 3.14159265358979323846 / 180.0;
bool valid(ASGeodetic point) {
    return std::isfinite(point.latitude) && std::isfinite(point.longitude) &&
           std::abs(point.latitude) <= 90.0 && std::abs(point.longitude) <= 180.0;
}
double signed_degrees(double value) {
    double angle = std::fmod(value + 180.0, 360.0);
    if (angle < 0.0) angle += 360.0;
    return angle - 180.0;
}
}

extern "C" ASStatus as_geodesic(ASGeodetic observer, ASGeodetic target,
                                   double *distance_m, double *bearing_deg) {
    if (!valid(observer) || !valid(target) || !distance_m || !bearing_deg)
        return AS_INVALID_ARGUMENT;
    const double lat1 = observer.latitude * kRadiansPerDegree;
    const double lat2 = target.latitude * kRadiansPerDegree;
    const double delta_lat = lat2 - lat1;
    const double delta_lon = signed_degrees(target.longitude - observer.longitude) * kRadiansPerDegree;
    const double a = std::pow(std::sin(delta_lat / 2.0), 2) +
                     std::cos(lat1) * std::cos(lat2) * std::pow(std::sin(delta_lon / 2.0), 2);
    const double bounded = std::clamp(a, 0.0, 1.0);
    *distance_m = 2.0 * kEarthRadiusMeters *
                  std::atan2(std::sqrt(bounded), std::sqrt(1.0 - bounded));
    const double east = std::sin(delta_lon) * std::cos(lat2);
    const double north = std::cos(lat1) * std::sin(lat2) -
                         std::sin(lat1) * std::cos(lat2) * std::cos(delta_lon);
    double bearing = std::atan2(east, north) / kRadiansPerDegree;
    if (bearing < 0.0) bearing += 360.0;
    *bearing_deg = bearing;
    return AS_OK;
}

extern "C" ASStatus as_local_enu(ASGeodetic origin, ASGeodetic target,
                                    double elevation_difference_m, ASVector3 *result) {
    if (!result || !std::isfinite(elevation_difference_m)) return AS_INVALID_ARGUMENT;
    double distance = 0.0;
    double bearing = 0.0;
    if (as_geodesic(origin, target, &distance, &bearing) != AS_OK || distance > 50000.0)
        return AS_INVALID_ARGUMENT;
    const double radians = bearing * kRadiansPerDegree;
    *result = {distance * std::sin(radians), distance * std::cos(radians), elevation_difference_m};
    return AS_OK;
}
