#ifndef AEROSPATIAL_ADAPTIVE_H
#define AEROSPATIAL_ADAPTIVE_H
#include "aerospatial_native.h"
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Optional visual/diagnostic compute ONLY. Quality 0=full, 3=minimal.
   Do not apply this governor to safety, flight telemetry or command paths. */
typedef struct {
    uint64_t last_ns;
    uint64_t last_adjustment_ns;
    uint32_t quality;
    uint32_t healthy_samples;
    double latency_ema_ms;
    int initialized;
} ASAdaptiveState;
ASStatus as_adaptive_update(ASAdaptiveState *state, uint64_t monotonic_ns,
                             uint32_t pressure_permille, uint32_t thermal_level,
                             double observed_latency_ms, double budget_ms,
                             uint32_t *selected_quality);

/* Prediction is a UI-only operator intent cue, never an actuator command.
   Yaw wraps at +/-180 degrees. The caller must reject stale external samples. */
typedef struct {
    double timestamp_seconds;
    double yaw_deg, pitch_deg;
    double yaw_rate_deg_s, pitch_rate_deg_s;
    int initialized;
} ASHeadIntentState;
typedef struct {
    double predicted_yaw_deg, predicted_pitch_deg;
    double yaw_rate_deg_s, pitch_rate_deg_s;
} ASHeadIntentPrediction;
ASStatus as_head_intent_predict(ASHeadIntentState *state,
                                double monotonic_seconds, double yaw_deg, double pitch_deg,
                                double horizon_seconds, ASHeadIntentPrediction *result);
#ifdef __cplusplus
}
#endif
#endif
