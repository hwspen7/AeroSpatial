#include "include/aerospatial_adaptive.h"
#include <algorithm>
#include <cmath>
#include <limits>

namespace {
double wrap(double angle) {
    angle = std::fmod(angle + 180.0, 360.0);
    if (angle < 0) angle += 360.0;
    return angle - 180.0;
}
}

extern "C" ASStatus as_adaptive_update(ASAdaptiveState *state, uint64_t monotonic_ns,
                                        uint32_t pressure_permille, uint32_t thermal_level,
                                        double observed_latency_ms, double budget_ms,
                                        uint32_t *selected_quality) {
    if (!state || !selected_quality || monotonic_ns == 0 || pressure_permille > 1000 ||
        thermal_level > 3 || !std::isfinite(observed_latency_ms) ||
        !std::isfinite(budget_ms) || observed_latency_ms < 0 ||
        budget_ms <= 0 || budget_ms > 60000 ||
        (state->initialized && (state->quality > 3 || monotonic_ns <= state->last_ns))) {
        return AS_INVALID_ARGUMENT;
    }
    ASAdaptiveState next = *state;
    const bool severe = pressure_permille >= 950 || thermal_level == 3 ||
                        observed_latency_ms > 2.0 * budget_ms;
    const bool overloaded = pressure_permille >= 800 || thermal_level >= 2 ||
                            observed_latency_ms > budget_ms;
    const bool healthy = pressure_permille < 400 && thermal_level == 0 &&
                         observed_latency_ms < 0.65 * budget_ms;
    if (!next.initialized) {
        next = {monotonic_ns, monotonic_ns, 0u, 0u, observed_latency_ms, 1};
    } else {
        const uint64_t elapsed = monotonic_ns - next.last_adjustment_ns;
        next.latency_ema_ms = 0.875 * next.latency_ema_ms + 0.125 * observed_latency_ms;
        if (overloaded) {
            next.quality = std::min(3u, next.quality + (severe ? 2u : 1u));
            next.healthy_samples = 0;
            next.last_adjustment_ns = monotonic_ns;
        } else if (healthy) {
            next.healthy_samples = std::min(100u, next.healthy_samples + 1u);
            if (next.healthy_samples >= 4 && elapsed >= 250000000ULL) {
                if (next.quality) --next.quality;
                next.healthy_samples = 0;
                next.last_adjustment_ns = monotonic_ns;
            }
        } else next.healthy_samples = 0;
        next.last_ns = monotonic_ns;
    }
    *state = next;
    *selected_quality = next.quality;
    return AS_OK;
}

extern "C" ASStatus as_head_intent_predict(ASHeadIntentState *state,
                                            double seconds, double yaw_deg, double pitch_deg,
                                            double horizon_seconds, ASHeadIntentPrediction *result) {
    if (!state || !result || !std::isfinite(seconds) || seconds < 0 ||
        !std::isfinite(yaw_deg) || yaw_deg < -180 || yaw_deg > 180 ||
        !std::isfinite(pitch_deg) || pitch_deg < -90 || pitch_deg > 90 ||
        !std::isfinite(horizon_seconds) || horizon_seconds < 0 || horizon_seconds > 0.5 ||
        (state->initialized && seconds <= state->timestamp_seconds)) return AS_INVALID_ARGUMENT;
    ASHeadIntentState next = *state;
    if (!next.initialized) {
        next = {seconds, yaw_deg, pitch_deg, 0, 0, 1};
    } else {
        const double dt = seconds - next.timestamp_seconds;
        if (dt > 1.0) {
            next = {seconds, yaw_deg, pitch_deg, 0, 0, 1};
        } else {
            const double delta_yaw = wrap(yaw_deg - next.yaw_deg);
            const double delta_pitch = pitch_deg - next.pitch_deg;
            if (dt < 0.005 || std::abs(delta_yaw / dt) > 720 ||
                std::abs(delta_pitch / dt) > 720) return AS_OUTLIER_REJECTED;
            const double smoothing = std::min(0.6, dt / (0.08 + dt));
            next.yaw_rate_deg_s = std::clamp((1-smoothing)*next.yaw_rate_deg_s +
                smoothing * delta_yaw / dt, -180.0, 180.0);
            next.pitch_rate_deg_s = std::clamp((1-smoothing)*next.pitch_rate_deg_s +
                smoothing * delta_pitch / dt, -180.0, 180.0);
            next.yaw_deg = yaw_deg;
            next.pitch_deg = pitch_deg;
            next.timestamp_seconds = seconds;
        }
    }
    const ASHeadIntentPrediction predicted{
        wrap(next.yaw_deg + next.yaw_rate_deg_s * horizon_seconds),
        std::clamp(next.pitch_deg + next.pitch_rate_deg_s * horizon_seconds, -90.0, 90.0),
        next.yaw_rate_deg_s, next.pitch_rate_deg_s
    };
    *state = next;
    *result = predicted;
    return AS_OK;
}
