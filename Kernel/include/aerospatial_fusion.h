#ifndef AEROSPATIAL_FUSION_H
#define AEROSPATIAL_FUSION_H
#include "aerospatial_estimation.h"
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ASFusion ASFusion;
typedef struct {
    uint64_t predicted, corrected, rejected_time, rejected_outlier, rejected_invalid, resets;
    double last_nis;
    uint64_t last_imu_sequence, last_position_sequence;
    uint32_t healthy;
} ASFusionReport;

/// Online non-actuating ESKF wrapper. Caller MUST provide actual calibrated
/// ENU position, body IMU, consistent monotonic seconds and calibrated noise.
/// IMU and position sequences are independently strictly increasing. Position
/// timestamps must equal the current filter time; delayed updates are rejected
/// rather than silently applied to the wrong state. Not a navigation guarantee.
ASFusion *as_fusion_create(double time_seconds, ASPose3 initial_pose,
                           const double standard_deviations[5], ASInertialNoise noise);
void as_fusion_destroy(ASFusion *fusion);
ASStatus as_fusion_imu(ASFusion *fusion, uint64_t sequence, double time_seconds,
                       ASVector3 specific_force, ASVector3 angular_velocity);
ASStatus as_fusion_position(ASFusion *fusion, uint64_t sequence, double time_seconds,
                            ASVector3 position_enu, double standard_deviation_m,
                            double maximum_nis);
/// Optional bounded delayed position update. Replays at most 255 subsequent IMU
/// checkpoints transactionally, including accepted position updates. The source
/// time must match a retained IMU checkpoint within 1 microsecond; no timestamp
/// interpolation, capture-time inference or metric frame registration occurs.
/// No update is committed if a later accepted position becomes inconsistent.
ASStatus as_fusion_position_replay(ASFusion *fusion, uint64_t sequence,
                                   double time_seconds, ASVector3 position_enu,
                                   double standard_deviation_m, double maximum_nis);
int as_fusion_snapshot(const ASFusion *fusion, ASInertialState *state, ASFusionReport *report);
#ifdef __cplusplus
}
#endif
#endif
