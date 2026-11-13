#include "test_common.h"
#include "aerospatial_estimation.h"
#include <cmath>
#include <cstring>
int main() {
    ASInertialState state{};
    ASPose3 origin{{0, 0, 0}, {1, 0, 0, 0}};
    const double deviations[5] = {5, 1, .25, .1, .1};
    REQUIRE(as_inertial_initialize(&state, 0, origin, deviations) == AS_OK);
    ASCovarianceQuality quality{};
    REQUIRE(as_inertial_covariance_quality(&state, 1e-12, &quality) == AS_OK);
    REQUIRE(quality.valid && quality.minimum_variance > 0);
    REQUIRE(std::abs(quality.quaternion_norm_error) < 1e-12);
    double nees = -1;
    REQUIRE(as_inertial_position_nees(&state, {0, 0, 0}, &nees) == AS_OK);
    REQUIRE(nees == 0);
    REQUIRE(as_inertial_position_nees(&state, {5, 0, 0}, &nees) == AS_OK);
    REQUIRE(std::abs(nees - 1) < 1e-9);
    const ASInertialNoise noise{.08, .005, .005, .0005, .1};
    for (int i = 1; i <= 200; ++i) {
        REQUIRE(as_inertial_predict(&state, .01 * i, {0, 0, 9.80665},
                                    {0, 0, 0}, noise) == AS_OK);
        REQUIRE(as_inertial_covariance_quality(&state, 1e-12, &quality) == AS_OK);
        REQUIRE(quality.valid);
        if (i % 20 == 0) {
            double nis = 0;
            REQUIRE(as_inertial_update_position(&state, {0.1, -0.1, 0.05},
                                                .5, 100, &nis) == AS_OK);
            REQUIRE(std::isfinite(nis) && nis >= 0 && nis < 100);
            REQUIRE(as_inertial_position_nees(&state, {0, 0, 0}, &nees) == AS_OK);
            REQUIRE(std::isfinite(nees) && nees >= 0);
        }
    }
    const auto untouched = state;
    state.covariance[0] = -1;
    REQUIRE(as_inertial_covariance_quality(&state, 1e-12, &quality) == AS_OK);
    REQUIRE(!quality.valid);
    REQUIRE(as_inertial_position_nees(&state, {0, 0, 0}, &nees) == AS_INVALID_ARGUMENT);
    state = untouched;
    state.covariance[1] += 1;
    REQUIRE(as_inertial_covariance_quality(&state, 1e-12, &quality) == AS_OK &&
            !quality.valid);
    state = untouched;
    state.body_to_enu.w = 2;
    REQUIRE(as_inertial_covariance_quality(&state, 1e-12, &quality) == AS_OK &&
            !quality.valid);
    REQUIRE(as_inertial_covariance_quality(nullptr, 1e-12, &quality) == AS_INVALID_ARGUMENT);
}
