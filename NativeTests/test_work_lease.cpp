#include "../Kernel/include/aerospatial_work_queue.h"
#include "test_common.h"
#include <cstdint>
int main(){
    ASWorkQueue *queue=as_work_queue_create(2,32,16);
    REQUIRE(queue);
    const uint8_t bytes[]={4,5,6,7};
    const ASWorkHeader header={1,10,100,0,ASWQ_OPTIONAL};
    REQUIRE(as_work_queue_push(queue,header,bytes,4,10)==ASWQ_OK);
    ASWorkLease *lease=nullptr;ASWorkHeader got{};
    REQUIRE(as_work_queue_pop_lease(queue,20,&got,&lease)==ASWQ_OK);
    REQUIRE(lease && got.trace_id==1);
    size_t length=0;
    const uint8_t *borrow=as_work_lease_data(lease,&length);
    REQUIRE(length==4 && borrow[0]==4 && borrow[3]==7);
    ASWorkStats stats{};
    REQUIRE(as_work_queue_stats(queue,&stats)==1 && stats.queue_bytes==0);
    as_work_queue_destroy(queue);
    REQUIRE(as_work_lease_data(lease,&length)[1]==5);
    as_work_lease_release(lease);
    return 0;
}
