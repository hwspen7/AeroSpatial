#include "include/aerospatial_estimation.h"
#include <algorithm>
#include <cmath>

namespace {
using M3 = double[9];
constexpr double kSmall = 1e-8;
bool finite3(ASVector3 p) { return std::isfinite(p.x) && std::isfinite(p.y) && std::isfinite(p.z); }
bool normalize(ASQuaternion q, ASQuaternion &r) {
    const double n = std::hypot(std::hypot(q.w, q.x), std::hypot(q.y, q.z));
    if (!std::isfinite(n) || n < 1e-12) return false;
    r = {q.w/n, q.x/n, q.y/n, q.z/n}; return true;
}
void skew(const double w[3], M3 s) {
    const double x=w[0],y=w[1],z=w[2];
    const double t[9]={0,-z,y,z,0,-x,-y,x,0};std::copy(t,t+9,s);
}
void mul3(const M3 a,const M3 b,M3 c){
    for(int i=0;i<3;++i)for(int j=0;j<3;++j){double v=0;for(int k=0;k<3;++k)v+=a[3*i+k]*b[3*k+j];c[3*i+j]=v;}
}
void matvec(const M3 a,const double b[3],double c[3]){
    for(int i=0;i<3;++i)c[i]=a[3*i]*b[0]+a[3*i+1]*b[1]+a[3*i+2]*b[2];
}
void left_jacobian(const double w[3], M3 v){
    const double t2=w[0]*w[0]+w[1]*w[1]+w[2]*w[2];
    if(t2>1e12){std::fill(v,v+9,0);return;}
    const double t=std::sqrt(t2);
    const double a=t<kSmall? .5-t2/24+t2*t2/720:(1-std::cos(t))/t2;
    const double b=t<kSmall? 1./6-t2/120+t2*t2/5040:(t-std::sin(t))/(t2*t);
    M3 s{},ss{};skew(w,s);mul3(s,s,ss);
    for(int i=0;i<9;++i)v[i]=(i%4==0?1.:0.)+a*s[i]+b*ss[i];
}
void rotation(ASQuaternion q,M3 r){
    const double w=q.w,x=q.x,y=q.y,z=q.z;
    const double a[9]={1-2*(y*y+z*z),2*(x*y-w*z),2*(x*z+w*y),
        2*(x*y+w*z),1-2*(x*x+z*z),2*(y*z-w*x),
        2*(x*z-w*y),2*(y*z+w*x),1-2*(x*x+y*y)};
    std::copy(a,a+9,r);
}
bool covariance_psd(const double p[36]) {
    double lower[36]{};
    for (int i=0;i<6;++i) for(int j=0;j<=i;++j) {
        if(!std::isfinite(p[6*i+j]) || !std::isfinite(p[6*j+i]) ||
           std::abs(p[6*i+j]-p[6*j+i])>1e-8*std::max({1.,std::abs(p[6*i+j]),std::abs(p[6*j+i])}))return false;
        double sum=.5*(p[6*i+j]+p[6*j+i]);
        for(int k=0;k<j;++k)sum-=lower[6*i+k]*lower[6*j+k];
        if(i==j){
            if(sum < -1e-10)return false;
            lower[6*i+j]=std::sqrt(std::max(1e-12,sum));
        } else {
            lower[6*i+j]=sum/lower[6*j+j];
        }
    }
    return true;
}
ASQuaternion product(ASQuaternion a,ASQuaternion b){return {
    a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z,
    a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
    a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
    a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w};}
bool inverse3(const M3 a,M3 inv){
    const double det=a[0]*(a[4]*a[8]-a[5]*a[7])-a[1]*(a[3]*a[8]-a[5]*a[6])+a[2]*(a[3]*a[7]-a[4]*a[6]);
    if(!std::isfinite(det)||std::abs(det)<1e-15)return false;
    const double b[9]={a[4]*a[8]-a[5]*a[7],a[2]*a[7]-a[1]*a[8],a[1]*a[5]-a[2]*a[4],
        a[5]*a[6]-a[3]*a[8],a[0]*a[8]-a[2]*a[6],a[2]*a[3]-a[0]*a[5],
        a[3]*a[7]-a[4]*a[6],a[1]*a[6]-a[0]*a[7],a[0]*a[4]-a[1]*a[3]};
    for(int i=0;i<9;++i)inv[i]=b[i]/det;
    return true;
}
}
extern "C" ASStatus as_pose_exp(const double *twist, ASPose3 *out){
    if(!twist||!out)return AS_INVALID_ARGUMENT;
    for(int i=0;i<6;++i)if(!std::isfinite(twist[i])||std::abs(twist[i])>1e8)return AS_INVALID_ARGUMENT;
    const double *w=twist+3;
    const double angle=std::hypot(std::hypot(w[0],w[1]),w[2]);
    if(angle>1e5)return AS_INVALID_ARGUMENT;
    const double half=.5*angle;
    const double coeff=angle<kSmall? .5-angle*angle/48:std::sin(half)/angle;
    ASQuaternion q{std::cos(half),coeff*w[0],coeff*w[1],coeff*w[2]};
    M3 j{};left_jacobian(w,j);double p[3]{};matvec(j,twist,p);
    if(!std::isfinite(p[0])||!std::isfinite(p[1])||!std::isfinite(p[2]))return AS_INVALID_ARGUMENT;
    *out={{p[0],p[1],p[2]},q};return AS_OK;
}
extern "C" ASStatus as_pose_log(ASPose3 input,double *twist){
    if(!twist||!finite3(input.translation_m))return AS_INVALID_ARGUMENT;
    ASQuaternion q{};if(!normalize(input.rotation,q))return AS_INVALID_ARGUMENT;
    if(q.w<0)q={-q.w,-q.x,-q.y,-q.z};
    const double s=std::hypot(std::hypot(q.x,q.y),q.z);
    const double angle=2*std::atan2(s,q.w);
    const double coeff=s<1e-12? 2.:angle/s;
    const double w[3]={q.x*coeff,q.y*coeff,q.z*coeff};
    M3 j{},inv{};left_jacobian(w,j);
    if(!inverse3(j,inv))return AS_INVALID_ARGUMENT;
    const double p[3]={input.translation_m.x,input.translation_m.y,input.translation_m.z};
    double v[3]{};matvec(inv,p,v);
    for(int i=0;i<3;++i){
        if(!std::isfinite(v[i]))return AS_INVALID_ARGUMENT;
        twist[i]=v[i];twist[3+i]=w[i];
    }
    return AS_OK;
}
extern "C" ASStatus as_pose_compose(ASPose3 a,ASPose3 b,ASPose3 *out){
    if(!out||!finite3(a.translation_m)||!finite3(b.translation_m))return AS_INVALID_ARGUMENT;
    ASQuaternion qa{},qb{},qr{};
    if(!normalize(a.rotation,qa)||!normalize(b.rotation,qb))return AS_INVALID_ARGUMENT;
    M3 r{};rotation(qa,r);const double t[3]={b.translation_m.x,b.translation_m.y,b.translation_m.z};
    double v[3]{};matvec(r,t,v);qr=product(qa,qb);if(!normalize(qr,qr))return AS_INVALID_ARGUMENT;
    const ASVector3 p{v[0]+a.translation_m.x,v[1]+a.translation_m.y,v[2]+a.translation_m.z};
    if(!finite3(p))return AS_INVALID_ARGUMENT;
    *out={p,qr};return AS_OK;
}
extern "C" ASStatus as_pose_inverse(ASPose3 a,ASPose3 *out){
    if(!out||!finite3(a.translation_m))return AS_INVALID_ARGUMENT;
    ASQuaternion q{};if(!normalize(a.rotation,q))return AS_INVALID_ARGUMENT;
    q={q.w,-q.x,-q.y,-q.z};
    M3 r{};rotation(q,r);
    const double t[3]={-a.translation_m.x,-a.translation_m.y,-a.translation_m.z};double v[3]{};
    matvec(r,t,v);
    if(!std::isfinite(v[0])||!std::isfinite(v[1])||!std::isfinite(v[2]))return AS_INVALID_ARGUMENT;
    *out={{v[0],v[1],v[2]},q};return AS_OK;
}
extern "C" ASStatus as_pose_covariance_compose(ASPose3 a,const double *pa,const double *pb,double *out){
    if(!pa||!pb||!out||!finite3(a.translation_m))return AS_INVALID_ARGUMENT;
    ASQuaternion q{};if(!normalize(a.rotation,q))return AS_INVALID_ARGUMENT;
    M3 r{},s{},sr{};rotation(q,r);const double t[]={a.translation_m.x,a.translation_m.y,a.translation_m.z};
    skew(t,s);mul3(s,r,sr);
    double ad[36]{};for(int i=0;i<3;++i)for(int j=0;j<3;++j){ad[i*6+j]=r[3*i+j];ad[i*6+j+3]=sr[3*i+j];ad[(i+3)*6+j+3]=r[3*i+j];}
    if(!covariance_psd(pa)||!covariance_psd(pb))return AS_INVALID_ARGUMENT;
    double temp[36]{},value[36]{};
    for(int i=0;i<6;++i)for(int j=0;j<6;++j)for(int k=0;k<6;++k)temp[i*6+j]+=ad[i*6+k]*pb[k*6+j];
    for(int i=0;i<6;++i)for(int j=0;j<6;++j){value[i*6+j]=pa[i*6+j];for(int k=0;k<6;++k)value[i*6+j]+=temp[i*6+k]*ad[j*6+k];}
    for(int i=0;i<6;++i)for(int j=0;j<=i;++j){const double sym=.5*(value[i*6+j]+value[j*6+i]);
        if(!std::isfinite(sym)||(i==j&&sym<0))return AS_INVALID_ARGUMENT;
        value[i*6+j]=value[j*6+i]=sym;}
    std::copy(value,value+36,out);return AS_OK;
}
