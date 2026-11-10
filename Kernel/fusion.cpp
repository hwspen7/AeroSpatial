#include "include/aerospatial_fusion.h"
#include <cmath>
#include <mutex>
#include <new>

struct ASFusion {
    mutable std::mutex lock;
    ASInertialState state{};
    ASInertialNoise noise{};
    ASFusionReport stats{};
};
extern "C" ASFusion *as_fusion_create(double time, ASPose3 pose,
                                       const double stds[5], ASInertialNoise noise) {
    if (!stds) return nullptr;
    auto *fusion=new(std::nothrow) ASFusion;
    if (!fusion)return nullptr;
    if (as_inertial_initialize(&fusion->state,time,pose,stds)!=AS_OK) {
        delete fusion;
        return nullptr;
    }
    // Validate all positive noise at construction; this is not a sensor calibration.
    const double vals[]={noise.accelerometer_std_mps2,noise.gyroscope_std_rps,
        noise.accelerometer_bias_walk_mps2,noise.gyroscope_bias_walk_rps,noise.maximum_step_s};
    for(double v:vals)if(!std::isfinite(v)||v<=0||v>1000){delete fusion;return nullptr;}
    fusion->noise=noise;
    fusion->stats.healthy=1;
    return fusion;
}
extern "C" void as_fusion_destroy(ASFusion *fusion){delete fusion;}
extern "C" ASStatus as_fusion_imu(ASFusion *fusion,uint64_t sequence,double time,
                                  ASVector3 force,ASVector3 gyro) {
    if (!fusion)return AS_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> guard(fusion->lock);
    if (!sequence || sequence<=fusion->stats.last_imu_sequence || !std::isfinite(time) ||
        time<=fusion->state.last_time_s) {
        ++fusion->stats.rejected_time;
        return AS_INVALID_ARGUMENT;
    }
    const ASStatus status=as_inertial_predict(&fusion->state,time,force,gyro,fusion->noise);
    if(status==AS_OK){fusion->stats.last_imu_sequence=sequence;++fusion->stats.predicted;}
    else if(status==AS_RESET_AFTER_GAP){++fusion->stats.resets;fusion->stats.healthy=0;}
    else ++fusion->stats.rejected_invalid;
    return status;
}
extern "C" ASStatus as_fusion_position(ASFusion *fusion,uint64_t sequence,double time,
                                       ASVector3 position,double std,double gate) {
    if (!fusion)return AS_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> guard(fusion->lock);
    const double delta=time-fusion->state.last_time_s;
    if (!sequence || sequence<=fusion->stats.last_position_sequence || !std::isfinite(delta) ||
        std::abs(delta)>1e-6) {
        ++fusion->stats.rejected_time;
        return AS_INVALID_ARGUMENT;
    }
    if (!fusion->stats.healthy) {++fusion->stats.rejected_invalid;return AS_INVALID_ARGUMENT;}
    double nis=0;
    const ASStatus status=as_inertial_update_position(&fusion->state,position,std,gate,&nis);
    if(status==AS_OK){fusion->stats.last_position_sequence=sequence;++fusion->stats.corrected;
        fusion->stats.last_nis=nis;}
    else if(status==AS_OUTLIER_REJECTED){++fusion->stats.rejected_outlier;fusion->stats.last_nis=nis;}
    else ++fusion->stats.rejected_invalid;
    return status;
}
extern "C" int as_fusion_snapshot(const ASFusion *fusion,ASInertialState *state,
                                   ASFusionReport *report) {
    if(!fusion||!state||!report)return 0;
    std::lock_guard<std::mutex> guard(fusion->lock);
    *state=fusion->state;*report=fusion->stats;return 1;
}
