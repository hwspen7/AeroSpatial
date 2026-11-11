#include "../Kernel/include/aerospatial_access_unit.h"
#include "test_common.h"
#include <cstdint>
#include <vector>

struct Received {
    unsigned nals=0, pictures=0, keyframes=0;
    std::vector<uint8_t> types;
};
static void nal(void *context, const uint8_t *bytes,size_t count,uint8_t type) {
    auto &r=*static_cast<Received *>(context);
    REQUIRE(bytes && count && (bytes[0]&31)==type);
    ++r.nals;
    r.types.push_back(type);
}
static void access(void *context,const ASH264AccessUnit *unit) {
    auto &r=*static_cast<Received *>(context);
    REQUIRE(unit && unit->avcc_size>4 && unit->sps_size && unit->pps_size);
    ++r.pictures;
    if(unit->keyframe)++r.keyframes;
}
int main(){
    auto *parser=as_h264_access_create(128,512);
    REQUIRE(parser);
    const uint8_t stream[]={0,0,1,0x67,0x42,0,0x1f,
       0,0,1,0x68,0xce,0x3c,
       0,0,1,0x65,0x80,0x55,
       0,0,1,0x41,0x80,0x66,
       0,0,1,0x09,0xf0};
    Received r;
    for(size_t i=0;i<sizeof(stream);++i)
        REQUIRE(as_h264_access_feed_dual(parser,stream+i,1,nal,access,&r)==ASH264_OK);
    // Final AUD terminates second frame when its next start code completes;
    // EOS flushes any still-pending picture.
    REQUIRE(as_h264_access_finish(parser,access,&r)==ASH264_OK);
    REQUIRE(r.nals>=4 && r.pictures==2 && r.keyframes==1);
    REQUIRE(r.types[0]==7 && r.types[1]==8);
    as_h264_access_destroy(parser);

    // An encoded stream without a trailing AUD still has a complete last
    // picture at a *confirmed* EOS. The dual API emits its final NAL too.
    auto *end_parser=as_h264_access_create(128,512);
    REQUIRE(end_parser);
    Received clean;
    const uint8_t unclosed[]={0,0,1,0x67,0x42,0,0x1f,
                                0,0,1,0x68,0xce,0x3c,
                                0,0,1,0x65,0x80,0x55};
    REQUIRE(as_h264_access_feed_dual(end_parser,unclosed,sizeof(unclosed),
                                      nal,access,&clean)==ASH264_OK);
    REQUIRE(clean.pictures==0 && clean.nals==2);
    REQUIRE(as_h264_access_finish_dual(end_parser,nal,access,&clean)==ASH264_OK);
    REQUIRE(clean.pictures==1 && clean.keyframes==1 && clean.nals==3);
    as_h264_access_destroy(end_parser);
}
