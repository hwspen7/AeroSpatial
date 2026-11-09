#ifndef AEROSPATIAL_NATIVE_H
#define AEROSPATIAL_NATIVE_H

#include <stddef.h>
#include "aerospatial_wire.h"
#include "aerospatial_qos.h"
#include "aerospatial_runtime.h"
#include "aerospatial_h264.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Stable C ABI. All distances use meters, angles degrees, times monotonic seconds. */
typedef struct { double x; double y; double z; } ASVector3;
typedef struct { double w; double x; double y; double z; } ASQuaternion;
typedef struct { double latitude; double longitude; } ASGeodetic;
typedef struct { double latitude; double longitude; double altitude; } ASGeodetic3;
typedef struct {
    double position;
    double velocity;
    double last_time;
    int initialized;
} ASFilterState;

typedef enum {
    AS_OK = 0,
    AS_INVALID_ARGUMENT = 1,
    AS_OUT_OF_ORDER = 2,
    AS_OUTLIER_REJECTED = 3,
    AS_RESET_AFTER_GAP = 4
} ASStatus;

/* Spherical geodesy, not survey-grade WGS84. Bearing clockwise from north. */
ASStatus as_geodesic(ASGeodetic observer, ASGeodetic target,
                     double *distance_m, double *bearing_deg);
/* Local east/north/up tangent approximation; rejects offsets beyond 50 km. */
ASStatus as_local_enu(ASGeodetic origin, ASGeodetic target,
                      double elevation_difference_m, ASVector3 *result);
/* WGS84 geodetic positions using ellipsoidal height in meters. */
ASStatus as_wgs84_ecef(ASGeodetic3 point, ASVector3 *result);
/* WGS84 ENU offset from origin; positions MUST share the same vertical datum. */
ASStatus as_wgs84_enu(ASGeodetic3 origin, ASGeodetic3 target, ASVector3 *result);
/* Right-handed ENU, intrinsic Z(yaw) Y(pitch) X(roll), angles in degrees. */
ASStatus as_euler_to_quaternion(double yaw, double pitch, double roll,
                                ASQuaternion *result);
ASStatus as_rotate_vector(ASQuaternion rotation, ASVector3 input, ASVector3 *result);
/* Normalized rotations and composition: product applies b, then a. */
ASStatus as_quaternion_inverse(ASQuaternion value, ASQuaternion *result);
ASStatus as_quaternion_multiply(ASQuaternion a, ASQuaternion b, ASQuaternion *result);
/* Unit-quaternion shortest-arc interpolation; t in [0,1]. */
ASStatus as_quaternion_slerp(ASQuaternion a, ASQuaternion b, double t, ASQuaternion *result);
/* A scalar smoothing and velocity tracking primitive, independent of hardware. */
void as_filter_reset(ASFilterState *state);
ASStatus as_filter_update(ASFilterState *state, double monotonic_time,
                          double measurement, double alpha, double beta,
                          double maximum_gap_s, double maximum_innovation,
                          double *position_out);
/* Allocation-free contiguous batch conversion. No partial writes on invalid input.
   Input and output arrays must not overlap. count may be zero. */
ASStatus as_wgs84_ecef_batch(const ASGeodetic3 *points, size_t count, ASVector3 *result);
/* In-place supported. Validates all samples before mutation. */
ASStatus as_lowpass_batch(const double *measurements, size_t count,
                          double alpha, double initial, double *result);
/* Pinhole camera coordinates: +X image right, +Y image down, +Z forward.
   Intrinsics must correspond to the encoded/decoded frame size and crop. */
typedef struct {
    double fx, fy, cx, cy;
    uint32_t width, height;
} ASCameraIntrinsics;
/* Returns a unit camera-frame ray (not a depth estimate). */
ASStatus as_camera_unproject(ASCameraIntrinsics camera, double pixel_x,
                             double pixel_y, ASVector3 *unit_ray);
/* Plane and camera position share the same local ENU origin and height datum.
   camera_to_enu transforms optical camera frame into ENU.
   Intersects only positive rays within max_distance_m. Not terrain mapping. */
ASStatus as_camera_ground_intersection(ASCameraIntrinsics camera, double pixel_x,
                                       double pixel_y, ASVector3 camera_enu,
                                       ASQuaternion camera_to_enu, double plane_up_m,
                                       double max_distance_m, ASVector3 *result);
/* Simple left/right stereo balance only; NOT HRTF spatial sound. */
ASStatus as_stereo_pan(double relative_bearing_deg, double *pan_out);

#ifdef __cplusplus
}
#endif
#include "aerospatial_adaptive.h"
#endif
