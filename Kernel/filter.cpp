#include "aerospatial_native.h"
#include <cmath>

extern "C" void as_filter_reset(ASFilterState *state) {
    if (state) *state = {0, 0, 0, 0};
}

extern "C" ASStatus as_filter_update(ASFilterState *state, double monotonic_time,
                                         double measurement, double alpha, double beta,
                                         double maximum_gap_s, double maximum_innovation,
                                         double *position_out) {
    if (!state || !position_out || !std::isfinite(monotonic_time) ||
        !std::isfinite(measurement) || !std::isfinite(alpha) || !std::isfinite(beta) ||
        !std::isfinite(maximum_gap_s) || !std::isfinite(maximum_innovation) ||
        alpha < 0 || alpha > 1 || beta < 0 || beta > 1 ||
        maximum_gap_s <= 0 || maximum_innovation <= 0) return AS_INVALID_ARGUMENT;
    if (!state->initialized) {
        *state = {measurement, 0, monotonic_time, 1};
        *position_out = measurement;
        return AS_OK;
    }
    const double delta = monotonic_time - state->last_time;
    if (!std::isfinite(delta) || delta <= 0) return AS_OUT_OF_ORDER;
    if (delta > maximum_gap_s) {
        *state = {measurement, 0, monotonic_time, 1};
        *position_out = measurement;
        return AS_RESET_AFTER_GAP;
    }
    const double prediction = state->position + delta*state->velocity;
    const double residual = measurement - prediction;
    if (!std::isfinite(prediction) || !std::isfinite(residual)) return AS_INVALID_ARGUMENT;
    if (std::abs(residual) > maximum_innovation) {
        *position_out = state->position;
        return AS_OUTLIER_REJECTED;
    }
    const double position = prediction + alpha*residual;
    const double velocity = state->velocity + (beta/delta)*residual;
    if (!std::isfinite(position) || !std::isfinite(velocity)) return AS_INVALID_ARGUMENT;
    *state = {position, velocity, monotonic_time, 1};
    *position_out = position;
    return AS_OK;
}

extern "C" ASStatus as_stereo_pan(double relative_bearing_deg, double *pan_out) {
    if (!pan_out || !std::isfinite(relative_bearing_deg)) return AS_INVALID_ARGUMENT;
    constexpr double kRad = 3.14159265358979323846 / 180.0;
    *pan_out = std::sin(std::remainder(relative_bearing_deg, 360.0) * kRad);
    return AS_OK;
}
