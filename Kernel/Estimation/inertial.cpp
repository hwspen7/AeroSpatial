#include "include/aerospatial_estimation.h"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace {
constexpr int N=15;
constexpr double G=9.80665;
bool valid(ASVector3 v){return std::isfinite(v.x)&&std::isfinite(v.y)&&std::isfinite(v.z);}
bool validquat(ASQuaternion q){return std::isfinite(q.w)&&std::isfinite(q.x)&&std::isfinite(q.y)&&std::isfinite(q.z)&&
    std::hypot(std::hypot(q.w,q.x),std::hypot(q.y,q.z))>1e-12;}
void norm(ASQuaternion &q){const double n=std::hypot(std::hypot(q.w,q.x),std::hypot(q.y,q.z));q.w/=n;q.x/=n;q.y/=n;q.z/=n;}
void rotate(ASQuaternion q,const double v[3],double out[3]){
    const double x=q.x,y=q.y,z=q.z,w=q.w;
    const double r[9]={1-2*(y*y+z*z),2*(x*y-w*z),2*(x*z+w*y),
        2*(x*y+w*z),1-2*(x*x+z*z),2*(y*z-w*x),
        2*(x*z-w*y),2*(y*z+w*x),1-2*(x*x+y*y)};
    for(int i=0;i<3;++i)out[i]=r[3*i]*v[0]+r[3*i+1]*v[1]+r[3*i+2]*v[2];
}
void rotmat(ASQuaternion q,double r[9]){
    const double axis[3][3]={{1,0,0},{0,1,0},{0,0,1}};
    for(int j=0;j<3;++j){double tmp[3];rotate(q,axis[j],tmp);for(int i=0;i<3;++i)r[3*i+j]=tmp[i];}
}
void skew(const double a[3],double s[9]){
    const double m[9]={0,-a[2],a[1],a[2],0,-a[0],-a[1],a[0],0};
    std::copy(m,m+9,s);
}
void crossmat(const double r[9],const double v[3],double out[9]){
    double s[9];skew(v,s);
    for(int i=0;i<3;++i)for(int j=0;j<3;++j){out[i*3+j]=0;for(int k=0;k<3;++k)out[i*3+j]+=r[i*3+k]*s[k*3+j];}
}
ASQuaternion mul(ASQuaternion a,ASQuaternion b){return {
    a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z,a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
    a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w};}
ASQuaternion dq(const double v[3]){
    const double t=std::hypot(std::hypot(v[0],v[1]),v[2]);
    const double k=t<1e-8? .5-t*t/48:std::sin(t/2)/t;
    return {std::cos(t/2),v[0]*k,v[1]*k,v[2]*k};
}
bool covariance_valid(const double p[225]){
    for(int i=0;i<N;++i){if(!std::isfinite(p[N*i+i])||p[N*i+i]<-1e-9)return false;
        for(int j=0;j<N;++j)if(!std::isfinite(p[N*i+j])||std::abs(p[N*i+j]-p[N*j+i])>1e-6)return false;}
    return true;
}
bool invert3(const double a[9],double out[9]){
    double m[3][6]{};
    for(int i=0;i<3;++i)for(int j=0;j<3;++j){m[i][j]=a[i*3+j];m[i][j+3]=i==j?1.:0.;}
    for(int k=0;k<3;++k){int pivot=k;for(int i=k+1;i<3;++i)if(std::abs(m[i][k])>std::abs(m[pivot][k]))pivot=i;
        if(!std::isfinite(m[pivot][k])||std::abs(m[pivot][k])<1e-14)return false;
        for(int j=0;j<6;++j)std::swap(m[pivot][j],m[k][j]);
        const double d=m[k][k];for(int j=0;j<6;++j)m[k][j]/=d;
        for(int i=0;i<3;++i)if(i!=k){const double f=m[i][k];for(int j=0;j<6;++j)m[i][j]-=f*m[k][j];}
    }
    for(int i=0;i<3;++i)for(int j=0;j<3;++j)out[i*3+j]=m[i][j+3];
    return true;
}
}
extern "C" ASStatus as_inertial_initialize(ASInertialState *state,double time,ASPose3 pose,const double *std){
    if(!state||!std||!std::isfinite(time)||time<0||!valid(pose.translation_m)||!validquat(pose.rotation))return AS_INVALID_ARGUMENT;
    for(int i=0;i<5;++i)if(!std::isfinite(std[i])||std[i]<=0||std[i]>1e5)return AS_INVALID_ARGUMENT;
    ASInertialState r{};r.position_m=pose.translation_m;r.body_to_enu=pose.rotation;norm(r.body_to_enu);
    for(int i=0;i<15;++i){int group=i/3;r.covariance[N*i+i]=std[group]*std[group];}
    r.last_time_s=time;r.initialized=1;*state=r;return AS_OK;
}
extern "C" ASStatus as_inertial_predict(ASInertialState *state,double time,ASVector3 force,
                                          ASVector3 omega,ASInertialNoise noise){
    if(!state||!state->initialized||!valid(force)||!valid(omega)||!std::isfinite(time)||
       !std::isfinite(state->last_time_s)||time<=state->last_time_s||!validquat(state->body_to_enu)||
       !valid(state->position_m)||!valid(state->velocity_mps)||!valid(state->accelerometer_bias_mps2)||
       !valid(state->gyroscope_bias_rps)||!covariance_valid(state->covariance))return AS_INVALID_ARGUMENT;
    const double values[5]={noise.accelerometer_std_mps2,noise.gyroscope_std_rps,
        noise.accelerometer_bias_walk_mps2,noise.gyroscope_bias_walk_rps,noise.maximum_step_s};
    for(double v:values)if(!std::isfinite(v)||v<=0||v>1000)return AS_INVALID_ARGUMENT;
    const double dt=time-state->last_time_s;
    if(dt>noise.maximum_step_s)return AS_RESET_AFTER_GAP;
    const double u[3]={force.x-state->accelerometer_bias_mps2.x,force.y-state->accelerometer_bias_mps2.y,
                       force.z-state->accelerometer_bias_mps2.z};
    const double w[3]={omega.x-state->gyroscope_bias_rps.x,omega.y-state->gyroscope_bias_rps.y,
                       omega.z-state->gyroscope_bias_rps.z};
    for(int i=0;i<3;++i)if(!std::isfinite(u[i])||!std::isfinite(w[i])||std::abs(u[i])>200||std::abs(w[i])>50)return AS_INVALID_ARGUMENT;
    ASInertialState next=*state;
    double r[9]{},a[3]{};rotmat(next.body_to_enu,r);rotate(next.body_to_enu,u,a);a[2]-=G;
    double p[3]={next.position_m.x,next.position_m.y,next.position_m.z};
    double v[3]={next.velocity_mps.x,next.velocity_mps.y,next.velocity_mps.z};
    for(int i=0;i<3;++i){p[i]+=v[i]*dt+.5*a[i]*dt*dt;v[i]+=a[i]*dt;}
    next.position_m={p[0],p[1],p[2]};next.velocity_mps={v[0],v[1],v[2]};
    const double delta[3]={dt*w[0],dt*w[1],dt*w[2]};next.body_to_enu=mul(next.body_to_enu,dq(delta));norm(next.body_to_enu);
    double f[225]{},temp[225]{},pc[225]{};
    for(int i=0;i<N;++i)f[N*i+i]=1;
    double rs[9]{},sw[9]{};crossmat(r,u,rs);skew(w,sw);
    for(int i=0;i<3;++i)for(int j=0;j<3;++j){
        f[N*i+(j+3)]=(i==j?dt:0);
        f[N*i+(j+6)]=-0.5*rs[3*i+j]*dt*dt;
        f[N*i+(j+9)]=-0.5*r[3*i+j]*dt*dt;
        f[N*(i+3)+(j+6)]=-rs[3*i+j]*dt;
        f[N*(i+3)+(j+9)]=-r[3*i+j]*dt;
        f[N*(i+6)+(j+6)]-=sw[3*i+j]*dt;
        f[N*(i+6)+(j+12)]=-dt*(i==j?1.:0.);
    }
    for(int i=0;i<N;++i)for(int j=0;j<N;++j)for(int k=0;k<N;++k)temp[N*i+j]+=f[N*i+k]*next.covariance[N*k+j];
    for(int i=0;i<N;++i)for(int j=0;j<N;++j)for(int k=0;k<N;++k)pc[N*i+j]+=temp[N*i+k]*f[N*j+k];
    const double a2=noise.accelerometer_std_mps2*noise.accelerometer_std_mps2;
    const double w2=noise.gyroscope_std_rps*noise.gyroscope_std_rps;
    const double ba2=noise.accelerometer_bias_walk_mps2*noise.accelerometer_bias_walk_mps2;
    const double bg2=noise.gyroscope_bias_walk_rps*noise.gyroscope_bias_walk_rps;
    // Discrete independent accelerometer noise feeds position and velocity; gyro noise feeds attitude.
    for(int i=0;i<3;++i)for(int j=0;j<3;++j){const double c=(i==j?1.:0.);
        pc[N*i+j]+=a2*std::pow(dt,4)*.25*c;
        pc[N*i+(j+3)]+=a2*std::pow(dt,3)*.5*c;
        pc[N*(i+3)+j]+=a2*std::pow(dt,3)*.5*c;
        pc[N*(i+3)+(j+3)]+=a2*dt*dt*c;
        pc[N*(i+6)+(j+6)]+=w2*dt*dt*c;
        pc[N*(i+9)+(j+9)]+=ba2*dt*c;
        pc[N*(i+12)+(j+12)]+=bg2*dt*c;
    }
    for(int i=0;i<N;++i)for(int j=0;j<i;++j){const double m=.5*(pc[N*i+j]+pc[N*j+i]);pc[N*i+j]=pc[N*j+i]=m;}
    if(!valid(next.position_m)||!valid(next.velocity_mps)||!covariance_valid(pc))return AS_INVALID_ARGUMENT;
    std::copy(pc,pc+225,next.covariance);next.last_time_s=time;*state=next;return AS_OK;
}
extern "C" ASStatus as_inertial_update_position(ASInertialState *state,ASVector3 measurement,
                                                   double std,double gate,double *nis){
    if(!state||!state->initialized||!nis||!valid(measurement)||!valid(state->position_m)||
       !std::isfinite(std)||std<=0||std>1e5||!std::isfinite(gate)||gate<=0||!covariance_valid(state->covariance))return AS_INVALID_ARGUMENT;
    const double variance=std*std;
    double s[9]{},si[9]{};for(int i=0;i<3;++i)for(int j=0;j<3;++j)
        s[3*i+j]=state->covariance[N*i+j]+(i==j?variance:0);
    if(!invert3(s,si))return AS_INVALID_ARGUMENT;
    const double innovation[3]={measurement.x-state->position_m.x,
                                  measurement.y-state->position_m.y,measurement.z-state->position_m.z};
    double y[3]{};for(int i=0;i<3;++i)for(int j=0;j<3;++j)y[i]+=si[3*i+j]*innovation[j];
    const double d=innovation[0]*y[0]+innovation[1]*y[1]+innovation[2]*y[2];
    if(!std::isfinite(d))return AS_INVALID_ARGUMENT;
    *nis=d;if(d>gate)return AS_OUTLIER_REJECTED;
    double k[45]{},dx[15]{};
    for(int i=0;i<N;++i)for(int j=0;j<3;++j)for(int a=0;a<3;++a)
        k[3*i+j]+=state->covariance[N*i+a]*si[3*a+j];
    for(int i=0;i<N;++i)for(int j=0;j<3;++j)dx[i]+=k[3*i+j]*innovation[j];
    ASInertialState next=*state;
    next.position_m.x+=dx[0];next.position_m.y+=dx[1];next.position_m.z+=dx[2];
    next.velocity_mps.x+=dx[3];next.velocity_mps.y+=dx[4];next.velocity_mps.z+=dx[5];
    next.accelerometer_bias_mps2.x+=dx[9];next.accelerometer_bias_mps2.y+=dx[10];next.accelerometer_bias_mps2.z+=dx[11];
    next.gyroscope_bias_rps.x+=dx[12];next.gyroscope_bias_rps.y+=dx[13];next.gyroscope_bias_rps.z+=dx[14];
    next.body_to_enu=mul(next.body_to_enu,dq(dx+6));norm(next.body_to_enu);
    // Joseph form (I-KH)P(I-KH)^T + KRK^T, then orientation-error reset.
    double ikh[225]{},tmp[225]{},pc[225]{};
    for(int i=0;i<N;++i){ikh[N*i+i]=1;for(int j=0;j<3;++j)ikh[N*i+j]-=k[3*i+j];}
    for(int i=0;i<N;++i)for(int j=0;j<N;++j)for(int h=0;h<N;++h)tmp[N*i+j]+=ikh[N*i+h]*next.covariance[N*h+j];
    for(int i=0;i<N;++i)for(int j=0;j<N;++j){for(int h=0;h<N;++h)pc[N*i+j]+=tmp[N*i+h]*ikh[N*j+h];
        for(int h=0;h<3;++h)pc[N*i+j]+=variance*k[3*i+h]*k[3*j+h];}
    double g[225]{};for(int i=0;i<N;++i)g[N*i+i]=1;
    double sk[9]{};skew(dx+6,sk);
    for(int i=0;i<3;++i)for(int j=0;j<3;++j)g[N*(6+i)+(6+j)]-=.5*sk[3*i+j];
    std::fill(tmp,tmp+225,0);std::fill(next.covariance,next.covariance+225,0);
    for(int i=0;i<N;++i)for(int j=0;j<N;++j)for(int h=0;h<N;++h)tmp[N*i+j]+=g[N*i+h]*pc[N*h+j];
    for(int i=0;i<N;++i)for(int j=0;j<N;++j)for(int h=0;h<N;++h)
        next.covariance[N*i+j]+=tmp[N*i+h]*g[N*j+h];
    for(int i=0;i<N;++i)for(int j=0;j<i;++j){const double m=.5*(next.covariance[N*i+j]+next.covariance[N*j+i]);
        next.covariance[N*i+j]=next.covariance[N*j+i]=m;}
    if(!valid(next.position_m)||!valid(next.velocity_mps)||!valid(next.accelerometer_bias_mps2)||
       !valid(next.gyroscope_bias_rps)||!covariance_valid(next.covariance))return AS_INVALID_ARGUMENT;
    *state=next;return AS_OK;
}
