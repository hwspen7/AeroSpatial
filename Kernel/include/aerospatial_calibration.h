#ifndef AEROSPATIAL_CALIBRATION_H
#define AEROSPATIAL_CALIBRATION_H
#include "aerospatial_native.h"
#ifdef __cplusplus
extern "C" {
#endif

/* Optical Brown-Conrady coefficients in normalized pinhole coordinates. */
typedef struct { double k1, k2, k3, p1, p2; } ASLensDistortion;
/* Project a camera-frame direction to a distorted pixel. No terrain/depth estimate. */
ASStatus as_camera_project_distorted(ASCameraIntrinsics camera, ASLensDistortion lens,
                                     ASVector3 camera_ray, double *pixel_x, double *pixel_y);
/* Numerically invert distortion with a bounded Newton iteration. Unit output ray. */
ASStatus as_camera_unproject_distorted(ASCameraIntrinsics camera, ASLensDistortion lens,
                                       double pixel_x, double pixel_y, ASVector3 *unit_ray);

/* Clock fit inputs must be monotonic in each domain, with <= 128 samples.
   The robust Theil-Sen initializer is quadratic, intended for calibration batches,
   NOT the per-frame or flight-control callback. */
typedef struct { double source_seconds, host_seconds; } ASClockSample;
typedef struct {
    double scale, offset_seconds, residual_rms_seconds;
    double first_source_seconds, last_source_seconds;
    double drift_uncertainty_ppm;
    unsigned int inliers, rejected;
} ASClockFit;
/* Huber-resistant initial slope via pairwise median, median intercept, then
   least-squares refit on residual-gated inliers. May reject bad calibration. */
ASStatus as_clock_fit_robust(const ASClockSample *samples, size_t count,
                             double maximum_drift_ppm, double residual_gate_seconds,
                             ASClockFit *fit);
/* Estimated uncertainty includes RMS fit residual and worst-case extrapolation
   drift. Not a certified clock error bound. No uncontrolled extrapolation. */
ASStatus as_clock_translate(const ASClockFit *fit, double source_seconds,
                             double maximum_extrapolation_seconds,
                             double *host_seconds, double *estimated_uncertainty_seconds);
#ifdef __cplusplus
}
#endif
#endif
