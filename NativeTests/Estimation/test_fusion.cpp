#include "../Kernel/include/aerospatial_fusion.h"
#include <cassert>
#include <cmath>
int main() {
    const double deviations[]={1,1,.1,.1,.1};
    const ASPose3 pose={{0,0,0},{1,0,0,0}};
    const ASInertialNoise noise={.1,.01,.001,.001,.2};
    auto *f=as_fusion_create(1,pose,deviations,noise);
    assert(f);
    const ASVector3 gravity={0,0,9.80665}, zero={0,0,0};
    assert(as_fusion_imu(f,1,1.01,gravity,zero)==AS_OK);
    assert(as_fusion_imu(f,1,1.02,gravity,zero)==AS_INVALID_ARGUMENT);
    assert(as_fusion_position(f,1,1.01,{.1,.1,0},1,16)==AS_OK);
    assert(as_fusion_position(f,2,1.00,{0,0,0},1,16)==AS_INVALID_ARGUMENT);
    assert(as_fusion_position(f,2,1.01,{10000,0,0},1,16)==AS_OUTLIER_REJECTED);
    ASInertialState state{};ASFusionReport report{};
    assert(as_fusion_snapshot(f,&state,&report)==1);
    assert(report.predicted==1 && report.corrected==1 && report.rejected_outlier==1);
    assert(std::abs(state.position_m.x)<1);
    assert(as_fusion_imu(f,2,2.0,gravity,zero)==AS_RESET_AFTER_GAP);
    assert(as_fusion_snapshot(f,&state,&report)==1 && !report.healthy);
    assert(as_fusion_position(f,2,1.01,{0,0,0},1,16)==AS_INVALID_ARGUMENT);
    // Once a time gap invalidates the filter, future IMU packets cannot
    // silently make a stale estimate appear healthy again.
    assert(as_fusion_imu(f, 3, 1.02, gravity, zero)==AS_RESET_AFTER_GAP);
    as_fusion_destroy(f);

    // A late observation at an actual stored IMU checkpoint can be replayed,
    // including subsequent, previously accepted position corrections.
    auto *ordered=as_fusion_create(1,pose,deviations,noise);
    auto *delayed=as_fusion_create(1,pose,deviations,noise);
    assert(ordered && delayed);
    for (int i=1;i<=4;++i) {
        const double t=1.0+0.01*i;
        assert(as_fusion_imu(ordered,i,t,gravity,zero)==AS_OK);
        assert(as_fusion_imu(delayed,i,t,gravity,zero)==AS_OK);
        if (i==2) assert(as_fusion_position(ordered,1,t,{.2,0,0},.5,16)==AS_OK);
        if (i==4) assert(as_fusion_position(ordered,2,t,{.25,0,0},.5,16)==AS_OK);
    }
    assert(as_fusion_position(delayed,1,1.04,{.25,0,0},.5,16)==AS_OK);
    assert(as_fusion_position_replay(delayed,2,1.02,{.2,0,0},.5,16)==AS_OK);
    ASInertialState state_a{},state_b{};
    ASFusionReport report_a{},report_b{};
    assert(as_fusion_snapshot(ordered,&state_a,&report_a)==1);
    assert(as_fusion_snapshot(delayed,&state_b,&report_b)==1);
    assert(std::abs(state_a.position_m.x-state_b.position_m.x)<1e-5);
    assert(std::abs(state_a.velocity_mps.x-state_b.velocity_mps.x)<1e-5);
    assert(std::abs(state_a.covariance[0]-state_b.covariance[0])<1e-5);
    assert(report_b.corrected==2 && report_b.predicted==4 && report_b.healthy);
    const double before=state_b.position_m.x;
    assert(as_fusion_position_replay(delayed,3,1.025,{.1,0,0},.5,16)==AS_INVALID_ARGUMENT);
    assert(as_fusion_position_replay(delayed,3,1.02,{1e8,0,0},.5,16)==AS_OUTLIER_REJECTED);
    assert(as_fusion_snapshot(delayed,&state_b,&report_b)==1);
    assert(std::abs(state_b.position_m.x-before)<1e-12);
    assert(report_b.corrected==2 && report_b.rejected_outlier>=1);
    assert(as_fusion_position_replay(delayed,3,1.02,{.1,0,0},.5,16)==AS_OK);
    assert(as_fusion_position_replay(delayed,3,1.02,{.1,0,0},.5,16)==AS_INVALID_ARGUMENT);
    as_fusion_destroy(ordered);
    as_fusion_destroy(delayed);

    // Retained replay states are bounded even after many IMU packets.
    auto *bounded=as_fusion_create(1,pose,deviations,noise);
    assert(bounded);
    for (int i=1;i<=300;++i)
        assert(as_fusion_imu(bounded,i,1.0+i*.01,gravity,zero)==AS_OK);
    assert(as_fusion_position_replay(bounded,1,1.01,{0,0,0},1,16)==AS_INVALID_ARGUMENT);
    assert(as_fusion_position_replay(bounded,1,3.99,{0,0,0},1,16)==AS_OK);
    as_fusion_destroy(bounded);
}
