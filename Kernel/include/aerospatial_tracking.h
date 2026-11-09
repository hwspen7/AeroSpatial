#ifndef AEROSPATIAL_TRACKING_H
#define AEROSPATIAL_TRACKING_H
#include "aerospatial_native.h"
#ifdef __cplusplus
extern "C" {
#endif
/* Independent east/north constant-velocity Kalman axes in a local metric frame.
   Variances and covariance always use meters and seconds. NOT an aircraft autopilot. */
typedef struct {
    double position, velocity;
    double var_position, cov_position_velocity, var_velocity;
} ASCVAxis;
typedef struct {
    ASCVAxis east, north;
    double last_seconds;
    int initialized;
} ASPlanarTrack;
/* Observe one position. NIS gate uses two degrees of freedom. On outliers,
   the predicted state is retained and no observation correction applied. */
ASStatus as_planar_track_update(ASPlanarTrack *state, double seconds,
                                 double east_m, double north_m,
                                 double measurement_std_m, double accel_spectral_density,
                                 double maximum_nis, double *observed_nis);
#ifdef __cplusplus
}
#endif
#endif
