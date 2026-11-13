#include "test_common.h"
#include "../Kernel/include/aerospatial_tracking.h"
#include <cmath>
#include <limits>

int main() {
    ASPlanarTrack track{};
    double nis=0;
    for(int i=0;i<100;i++) {
        const double t=i*0.1;
        const double e=2*t+(i%3==0 ? 0.03:-0.02);
        const double n=-0.8*t+(i%4==0 ? -0.03:0.01);
        const auto status=as_planar_track_update(&track,t,e,n,0.2,0.01,16,&nis);
        REQUIRE(status==AS_OK);
        REQUIRE(nis>=0 && std::isfinite(nis));
        REQUIRE(track.east.var_position>=0 && track.north.var_position>=0);
    }
    REQUIRE(std::abs(track.east.velocity-2)<0.1);
    REQUIRE(std::abs(track.north.velocity+0.8)<0.1);
    REQUIRE(std::abs(track.east.position-19.8)<0.15);
    const double previous=track.east.position;
    REQUIRE(as_planar_track_update(&track,10,10000,10000,0.2,0.01,16,&nis)==AS_OUTLIER_REJECTED);
    REQUIRE(track.east.position<previous+1);
    REQUIRE(nis>16);
    const double old_t=track.last_seconds;
    REQUIRE(as_planar_track_update(&track,old_t,10,10,0.2,0.01,16,&nis)==AS_INVALID_ARGUMENT);
    REQUIRE(track.last_seconds==old_t);
    REQUIRE(as_planar_track_update(&track,40,10,10,0.2,0.01,16,&nis)==AS_RESET_AFTER_GAP);
    REQUIRE(track.east.position==10 && track.north.position==10);
    REQUIRE(as_planar_track_update(&track,40.1,std::numeric_limits<double>::quiet_NaN(),0,
                                   0.2,0.01,16,&nis)==AS_INVALID_ARGUMENT);
}
