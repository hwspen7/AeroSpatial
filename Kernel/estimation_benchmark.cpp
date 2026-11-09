#include "include/aerospatial_estimation.h"
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <iomanip>
int main(int argc,char **argv){
    const long count=argc>1?std::strtol(argv[1],nullptr,10):50000;
    if(count<1||count>3000000){std::cerr<<"invalid sample count\n";return 2;}
    ASInertialState s{};
    const double initial[]={1,1,.1,.1,.1};
    const ASPose3 p{{0,0,0},{1,0,0,0}};
    if(as_inertial_initialize(&s,0,p,initial)!=AS_OK)return 3;
    const ASInertialNoise noise{.08,.005,.005,.0005,.05};
    using clock=std::chrono::steady_clock;
    const auto start=clock::now();
    for(long i=1;i<=count;++i){
        if(as_inertial_predict(&s,.01*i,{.1,0,9.80665},{0,0,.001},noise)!=AS_OK)return 4;
        if(i%100==0){double nis=0;const auto status=as_inertial_update_position(&s,
            {s.position_m.x,s.position_m.y,s.position_m.z},2,11.3449,&nis);
            if(status!=AS_OK)return 5;}
    }
    const auto finish=clock::now();
    const double seconds=std::chrono::duration<double>(finish-start).count();
    std::cout<<std::setprecision(8)<<"{\"operation\":\"15_state_eskf_predict\",\"updates\":"
             <<count<<",\"seconds\":"<<seconds<<",\"updates_per_second\":"
             <<count/seconds<<",\"state_x_m\":"<<s.position_m.x<<"}\n";
}
