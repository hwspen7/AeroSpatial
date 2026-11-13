#include "include/aerospatial_estimation.h"
#include <algorithm>
#include <cmath>
#include <limits>

namespace {
constexpr int N = 15;
bool finite(ASVector3 v) {
    return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z);
}
double quat_norm(ASQuaternion q) {
    return std::hypot(std::hypot(q.w, q.x), std::hypot(q.y, q.z));
}
/* Strictly positive Cholesky, no heap allocations or implicit regularization.
   This must reject an invalid variance matrix rather than silently repair it. */
bool spd(const double p[225], double tolerance) {
    double l[225]{};
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j <= i; ++j) {
            double value = .5 * (p[i * N + j] + p[j * N + i]);
            for (int k = 0; k < j; ++k) value -= l[i * N + k] * l[j * N + k];
            if (!std::isfinite(value)) return false;
            if (i == j) {
                if (value <= tolerance) return false;
                l[i * N + j] = std::sqrt(value);
            } else l[i * N + j] = value / l[j * N + j];
        }
    }
    return true;
}
}
extern "C" ASStatus as_inertial_covariance_quality(
    const ASInertialState *state, double tolerance, ASCovarianceQuality *out) {
    if (!state || !out || !std::isfinite(tolerance) ||
        tolerance < 0 || tolerance > 1e-3 || !state->initialized)
        return AS_INVALID_ARGUMENT;
    ASCovarianceQuality quality{};
    quality.minimum_variance = std::numeric_limits<double>::infinity();
    const double qnorm = quat_norm(state->body_to_enu);
    quality.quaternion_norm_error = std::abs(qnorm - 1.);
    bool scalar_valid = std::isfinite(state->last_time_s) &&
        state->last_time_s >= 0 && finite(state->position_m) &&
        finite(state->velocity_mps) && finite(state->accelerometer_bias_mps2) &&
        finite(state->gyroscope_bias_rps) && std::isfinite(qnorm) &&
        quality.quaternion_norm_error <= 1e-5;
    for (int i = 0; i < N; ++i) {
        const double diagonal = state->covariance[i * N + i];
        if (!std::isfinite(diagonal)) scalar_valid = false;
        else {
            quality.trace += diagonal;
            quality.minimum_variance = std::min(quality.minimum_variance, diagonal);
            quality.maximum_variance = std::max(quality.maximum_variance, diagonal);
        }
        for (int j = 0; j < i; ++j) {
            const double x = state->covariance[i * N + j];
            const double y = state->covariance[j * N + i];
            if (!std::isfinite(x) || !std::isfinite(y)) scalar_valid = false;
            else quality.maximum_asymmetry =
                std::max(quality.maximum_asymmetry, std::abs(x - y));
        }
    }
    if (quality.maximum_asymmetry > tolerance || !std::isfinite(quality.trace))
        scalar_valid = false;
    quality.valid = scalar_valid && spd(state->covariance, tolerance) ? 1u : 0u;
    *out = quality;
    return AS_OK;
}
extern "C" ASStatus as_inertial_position_nees(
    const ASInertialState *state, ASVector3 truth, double *out) {
    if (!out || !finite(truth)) return AS_INVALID_ARGUMENT;
    ASCovarianceQuality quality{};
    if (as_inertial_covariance_quality(state, 1e-12, &quality) != AS_OK ||
        !quality.valid) return AS_INVALID_ARGUMENT;
    // Cholesky solve for 3x3 P_pos, then NEES = ||L^-1 residual||^2.
    double l[3][3]{};
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j <= i; ++j) {
            double v = state->covariance[15 * i + j];
            for (int k = 0; k < j; ++k) v -= l[i][k] * l[j][k];
            if (i == j) {
                if (!(v > 0) || !std::isfinite(v)) return AS_INVALID_ARGUMENT;
                l[i][j] = std::sqrt(v);
            } else l[i][j] = v / l[j][j];
        }
    }
    const double residual[3] = {
        truth.x - state->position_m.x,
        truth.y - state->position_m.y,
        truth.z - state->position_m.z
    };
    double whitened[3]{};
    double nees = 0;
    for (int i = 0; i < 3; ++i) {
        double v = residual[i];
        for (int j = 0; j < i; ++j) v -= l[i][j] * whitened[j];
        whitened[i] = v / l[i][i];
        nees += whitened[i] * whitened[i];
    }
    if (!std::isfinite(nees)) return AS_INVALID_ARGUMENT;
    *out = nees;
    return AS_OK;
}
