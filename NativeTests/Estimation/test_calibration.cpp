#include "test_common.h"
#include "../Kernel/include/aerospatial_calibration.h"
#include <array>
#include <cmath>
#include <limits>

static void lens_round_trip() {
    const ASCameraIntrinsics c{1000,990,640,360,1280,720};
    const ASLensDistortion l{-0.14,0.03,-0.002,0.002,-0.001};
    for(double py=30;py<700;py+=57) for(double px=40;px<1250;px+=73) {
        ASVector3 ray{};
        REQUIRE(as_camera_unproject_distorted(c,l,px,py,&ray)==AS_OK);
        REQUIRE(std::abs(std::hypot(std::hypot(ray.x,ray.y),ray.z)-1)<1e-12);
        double x=-1,y=-1;
        REQUIRE(as_camera_project_distorted(c,l,ray,&x,&y)==AS_OK);
        REQUIRE(std::abs(x-px)<1e-7 && std::abs(y-py)<1e-7);
    }
    ASVector3 a{},b{};
    REQUIRE(as_camera_unproject(c,100,100,&a)==AS_OK);
    REQUIRE(as_camera_unproject_distorted(c,{0,0,0,0,0},100,100,&b)==AS_OK);
    REQUIRE(std::abs(a.x-b.x)<1e-12 && std::abs(a.y-b.y)<1e-12);
    const ASVector3 sentinel{42,42,42};
    ASVector3 output=sentinel;
    REQUIRE(as_camera_unproject_distorted(c,l,-1,20,&output)==AS_INVALID_ARGUMENT);
    REQUIRE(output.x==42);
    REQUIRE(as_camera_unproject_distorted(c,{std::numeric_limits<double>::quiet_NaN(),0,0,0,0},20,20,&output)==AS_INVALID_ARGUMENT);
    REQUIRE(output.x==42);
    double px=99,py=99;
    REQUIRE(as_camera_project_distorted(c,l,{1,2,-1},&px,&py)==AS_INVALID_ARGUMENT);
    REQUIRE(px==99 && py==99);
}
static void robust_clock_with_outliers() {
    std::array<ASClockSample,32> s{};
    for(unsigned i=0;i<s.size();i++) {
        const double x=10000.0+0.5*i;
        s[i]={x,50.0+1.00008*x+(i%3==0 ? 0.0002:-0.0001)};
    }
    s[7].host_seconds+=0.15;
    s[19].host_seconds-=0.18;
    ASClockFit fit{};
    REQUIRE(as_clock_fit_robust(s.data(),s.size(),200,0.012,&fit)==AS_OK);
    REQUIRE(fit.inliers==30 && fit.rejected==2);
    REQUIRE(std::abs(fit.scale-1.00008)<0.000005);
    REQUIRE(std::abs(fit.offset_seconds-50)<0.05);
    REQUIRE(fit.residual_rms_seconds<0.001);
    double translated=0,uncertainty=0;
    REQUIRE(as_clock_translate(&fit,10001.25,2,&translated,&uncertainty)==AS_OK);
    REQUIRE(std::abs(translated-(50+1.00008*10001.25))<0.005);
    REQUIRE(uncertainty<0.001);
    REQUIRE(as_clock_translate(&fit,10020,2,&translated,&uncertainty)==AS_OUTLIER_REJECTED);
    REQUIRE(as_clock_translate(&fit,10017,2,&translated,&uncertainty)==AS_OK);
    REQUIRE(uncertainty>fit.residual_rms_seconds);
}
static void invalid_clock_rejection() {
    std::array<ASClockSample,4> s{{{1,1},{2,2},{3,3},{4,4}}};
    ASClockFit result{};
    REQUIRE(as_clock_fit_robust(s.data(),s.size(),100,0.01,&result)==AS_OK);
    REQUIRE(result.inliers==4);
    s[2].host_seconds=0.1;
    ASClockFit saved=result;
    REQUIRE(as_clock_fit_robust(s.data(),s.size(),100,0.01,&result)==AS_INVALID_ARGUMENT);
    REQUIRE(result.inliers==saved.inliers);
    REQUIRE(as_clock_fit_robust(s.data(),3,100,0.01,&result)==AS_INVALID_ARGUMENT);
    REQUIRE(as_clock_translate(&saved,-1,1,&s[0].source_seconds,&s[0].host_seconds)==AS_INVALID_ARGUMENT);
}
int main() { lens_round_trip(); robust_clock_with_outliers(); invalid_clock_rejection(); }
