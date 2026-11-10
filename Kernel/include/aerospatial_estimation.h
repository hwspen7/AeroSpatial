#ifndef AEROSPATIAL_ESTIMATION_H
#define AEROSPATIAL_ESTIMATION_H
#include "aerospatial_native.h"
#ifdef __cplusplus
extern "C" {
#endif

/* Tangent ordering: translation xyz, rotation xyz (radians).
   Rigid transforms map child coordinates into parent coordinates. */
typedef struct {
    ASVector3 translation_m;
    ASQuaternion rotation;
} ASPose3;

/* Exp/log in SE(3) with the left Jacobian of SO(3). */
ASStatus as_pose_exp(const double twist[6], ASPose3 *result);
ASStatus as_pose_log(ASPose3 pose, double twist[6]);
ASStatus as_pose_compose(ASPose3 parent_from_middle, ASPose3 middle_from_child, ASPose3 *result);
ASStatus as_pose_inverse(ASPose3 input, ASPose3 *result);
/* Column-major input is NOT used: 6x6 matrices are row-major.
   Independent left perturbation uncertainties: Sigma_AB = Sigma_A + Ad_A Sigma_B Ad_A^T. */
ASStatus as_pose_covariance_compose(ASPose3 a, const double covariance_a[36],
                                     const double covariance_b[36], double result[36]);

/* Error state ordering: position(0:3), velocity(3:6), orientation(6:9),
   accelerometer bias(9:12), gyroscope bias(12:15).
   Local world frame ENU, body-frame specific force (m/s^2), gyro (rad/s).
   Nominal quaternion rotates body vectors into ENU. */
typedef struct {
    ASVector3 position_m;
    ASVector3 velocity_mps;
    ASQuaternion body_to_enu;
    ASVector3 accelerometer_bias_mps2;
    ASVector3 gyroscope_bias_rps;
    double covariance[225]; /* Row-major 15x15 error covariance. */
    double last_time_s;
    int initialized;
} ASInertialState;

typedef struct {
    double accelerometer_std_mps2;
    double gyroscope_std_rps;
    double accelerometer_bias_walk_mps2;
    double gyroscope_bias_walk_rps;
    double maximum_step_s;
} ASInertialNoise;

/* Initializes from an independently established pose. NO self-alignment claim.
   Position/velocity/orientation/bias initial standard deviations (5 groups). */
ASStatus as_inertial_initialize(ASInertialState *state, double time_s, ASPose3 pose,
                                 const double initial_std[5]);
/* First-order discrete error dynamics with second-order position coupling.
   Rejects missing/late IMU gaps instead of extrapolating through them. */
ASStatus as_inertial_predict(ASInertialState *state, double time_s,
                             ASVector3 specific_force_body_mps2,
                             ASVector3 angular_velocity_body_rps, ASInertialNoise noise);
/* Position observation update, isotropic 3D noise, chi-square NIS gate.
   On a gated outlier the state is unchanged. No flight-control output. */
ASStatus as_inertial_update_position(ASInertialState *state, ASVector3 position_enu_m,
                                     double position_std_m, double maximum_nis, double *nis_out);

#ifdef __cplusplus
}
#endif
#include "aerospatial_fusion.h"
#endif
