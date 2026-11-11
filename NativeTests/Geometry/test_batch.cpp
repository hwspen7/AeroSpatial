#include "aerospatial_native.h"
#include "test_common.h"
#include <array>
#include <cmath>
#include <limits>

int main() {
    std::array<ASGeodetic3, 3> points{{{40, -83, 200}, {41, -84, 150}, {42, -85, 250}}};
    std::array<ASVector3, 3> output{};
    REQUIRE(as_wgs84_ecef_batch(points.data(), points.size(), output.data()) == AS_OK);
    for (size_t index = 0; index < points.size(); ++index) {
        ASVector3 scalar{};
        REQUIRE(as_wgs84_ecef(points[index], &scalar) == AS_OK);
        REQUIRE(std::abs(output[index].x - scalar.x) < 1e-7);
        REQUIRE(std::abs(output[index].y - scalar.y) < 1e-7);
    }
    const auto previous = output;
    points[2].latitude = 100;
    REQUIRE(as_wgs84_ecef_batch(points.data(), points.size(), output.data()) == AS_INVALID_ARGUMENT);
    REQUIRE(output[0].x == previous[0].x && output[1].x == previous[1].x);

    double samples[] = {10, 12, 14, 10};
    REQUIRE(as_lowpass_batch(samples, 4, 0.5, 0, samples) == AS_OK);
    REQUIRE(std::abs(samples[0] - 5.0) < 1e-12);
    REQUIRE(std::abs(samples[1] - 8.5) < 1e-12);
    samples[1] = std::numeric_limits<double>::quiet_NaN();
    const double initial = samples[0];
    REQUIRE(as_lowpass_batch(samples, 4, 0.5, 0, samples) == AS_INVALID_ARGUMENT);
    REQUIRE(samples[0] == initial);
    REQUIRE(as_lowpass_batch(nullptr, 0, 0.5, 0, nullptr) == AS_OK);
    return 0;
}
