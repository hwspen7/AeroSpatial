#include "test_common.h"
#include "../Kernel/include/aerospatial_estimation.h"
#include <cmath>
#include <cstring>

static bool close(double a,double b,double t=1e-8){return std::abs(a-b)<t;}
static void group_lie(){
    const double x[6]={1.2,-2.0,3.4,0.12,-0.23,.31};
    ASPose3 p{},inv{},id{};
    REQUIRE(as_pose_exp(x,&p)==AS_OK);
    double back[6]{};REQUIRE(as_pose_log(p,back)==AS_OK);
    for(int i=0;i<6;++i)REQUIRE(close(x[i],back[i]));
    REQUIRE(as_pose_inverse(p,&inv)==AS_OK);
    REQUIRE(as_pose_compose(p,inv,&id)==AS_OK);
    REQUIRE(close(id.translation_m.x,0)&&close(id.translation_m.y,0)&&close(id.translation_m.z,0));
    REQUIRE(close(id.rotation.w,1));
    double ca[36]{},cb[36]{},cc[36]{};
    for(int i=0;i<6;++i){ca[i*6+i]=1;cb[i*6+i]=.5;}
    REQUIRE(as_pose_covariance_compose(p,ca,cb,cc)==AS_OK);
    for(int i=0;i<6;++i)REQUIRE(cc[i*6+i]>=1.5-1e-8);
    const double zeros[6]={0};REQUIRE(as_pose_exp(zeros,&p)==AS_OK);
    REQUIRE(as_pose_covariance_compose(p,ca,cb,cc)==AS_OK);
    for(int i=0;i<36;++i)REQUIRE(close(cc[i],ca[i]+cb[i]));
    double broken[36]{}; broken[0]=-1;
    REQUIRE(as_pose_covariance_compose(p,broken,cb,cc)==AS_INVALID_ARGUMENT);
    broken[0]=1;broken[1]=2;
    REQUIRE(as_pose_covariance_compose(p,broken,cb,cc)==AS_INVALID_ARGUMENT);
    double nan[6]={NAN};REQUIRE(as_pose_exp(nan,&p)==AS_INVALID_ARGUMENT);
}
static void inertial(){
    ASInertialState state{};
    const ASPose3 home{{0,0,0},{1,0,0,0}};
    const double init[5]={5,1,.25,.1,.1};
    REQUIRE(as_inertial_initialize(&state,0,home,init)==AS_OK);
    const ASInertialNoise n{.08,.005,.005,.0005,.1};
    for(int i=1;i<=200;++i){
        REQUIRE(as_inertial_predict(&state,.01*i,{0,0,9.80665},{0,0,0},n)==AS_OK);
    }
    REQUIRE(close(state.position_m.x,0)&&close(state.position_m.y,0)&&close(state.position_m.z,0));
    REQUIRE(close(state.body_to_enu.w,1));
    for(int i=0;i<15;++i){REQUIRE(state.covariance[15*i+i]>0);
        for(int j=0;j<15;++j)REQUIRE(close(state.covariance[15*i+j],state.covariance[15*j+i],1e-7));}
    const auto before=state;
    double nis=0;
    REQUIRE(as_inertial_update_position(&state,{1000,0,0},1,11.3449,&nis)==AS_OUTLIER_REJECTED);
    REQUIRE(nis>11.3449);REQUIRE(std::memcmp(&before,&state,sizeof(state))==0);
    REQUIRE(as_inertial_update_position(&state,{2,-1,3},1,1000,&nis)==AS_OK);
    REQUIRE(state.position_m.x>0&&state.position_m.x<2);
    REQUIRE(state.position_m.y<0&&state.position_m.y>-1);
    REQUIRE(state.position_m.z>0&&state.position_m.z<3);
    const auto safe=state;
    REQUIRE(as_inertial_predict(&state,4,{0,0,9.80665},{0,0,0},n)==AS_RESET_AFTER_GAP);
    REQUIRE(std::memcmp(&safe,&state,sizeof(state))==0);
    REQUIRE(as_inertial_predict(&state,1,{0,0,9.80665},{0,0,0},n)==AS_INVALID_ARGUMENT);
    REQUIRE(as_inertial_update_position(&state,{NAN,0,0},1,12,&nis)==AS_INVALID_ARGUMENT);
}
int main(){group_lie();inertial();}
