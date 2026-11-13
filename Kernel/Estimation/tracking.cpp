#include "include/aerospatial_tracking.h"
#include <algorithm>
#include <cmath>

namespace {
void initialize(ASPlanarTrack &s,double t,double e,double n,double r) {
    s.east={e,0,r*r,0,100};
    s.north={n,0,r*r,0,100};
    s.last_seconds=t;
    s.initialized=1;
}
void predict(ASCVAxis &s,double dt,double q) {
    const double p=s.var_position,pv=s.cov_position_velocity,v=s.var_velocity;
    s.position+=s.velocity*dt;
    s.var_position=p+2*dt*pv+dt*dt*v+q*dt*dt*dt/3;
    s.cov_position_velocity=pv+dt*v+q*dt*dt/2;
    s.var_velocity=v+q*dt;
}
void correct(ASCVAxis &s,double residual,double measurement_var) {
    const double innovation_var=s.var_position+measurement_var;
    const double kp=s.var_position/innovation_var;
    const double kv=s.cov_position_velocity/innovation_var;
    const double old_cov=s.cov_position_velocity;
    s.position+=kp*residual;
    s.velocity+=kv*residual;
    // Scalar Kalman covariance correction, retaining symmetry and non-negative diagonals.
    s.var_position=std::max(0.0,(1-kp)*s.var_position);
    s.cov_position_velocity=(1-kp)*old_cov;
    s.var_velocity=std::max(0.0,s.var_velocity-kv*old_cov);
}
}
extern "C" ASStatus as_planar_track_update(ASPlanarTrack *state,double t,double e,double n,
                                             double stddev,double q,double gate,double *nis) {
    if(!state || !nis || !std::isfinite(t) || t<0 || !std::isfinite(e) ||
       !std::isfinite(n) || !std::isfinite(stddev) || stddev<=0 || stddev>10000 ||
       !std::isfinite(q) || q<0 || q>10000 || !std::isfinite(gate) || gate<=0 || gate>10000 ||
       (state->initialized && (!std::isfinite(state->last_seconds) ||
                               t<=state->last_seconds))) return AS_INVALID_ARGUMENT;
    if(!state->initialized) {
        initialize(*state,t,e,n,stddev);
        *nis=0;
        return AS_OK;
    }
    const double dt=t-state->last_seconds;
    if(dt>20) {
        initialize(*state,t,e,n,stddev);
        *nis=0;
        return AS_RESET_AFTER_GAP;
    }
    ASPlanarTrack predicted=*state;
    predict(predicted.east,dt,q);
    predict(predicted.north,dt,q);
    if(!std::isfinite(predicted.east.var_position) ||
       !std::isfinite(predicted.north.var_position)) return AS_INVALID_ARGUMENT;
    const double er=e-predicted.east.position,nr=n-predicted.north.position;
    const double variance=stddev*stddev;
    const double innovation=er*er/(predicted.east.var_position+variance)+
                            nr*nr/(predicted.north.var_position+variance);
    if(!std::isfinite(innovation)) return AS_INVALID_ARGUMENT;
    *nis=innovation;
    predicted.last_seconds=t;
    if(innovation>gate) {
        *state=predicted;
        return AS_OUTLIER_REJECTED;
    }
    correct(predicted.east,er,variance);
    correct(predicted.north,nr,variance);
    *state=predicted;
    return AS_OK;
}
