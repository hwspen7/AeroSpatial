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
    as_fusion_destroy(f);
}
