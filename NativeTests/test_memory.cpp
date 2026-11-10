#include "../Kernel/include/aerospatial_memory.h"
#include <cassert>
#include <cstdint>
#include <thread>
#include <vector>
int main() {
    auto *pool = as_memory_pool_create(16, 8);
    assert(pool);
    const uint8_t source[]={1,2,3,4,5,6,7,8};
    auto *a=as_memory_pool_copy(pool,source,8);
    auto *b=as_memory_lease_retain(a);
    assert(a && b);
    size_t size=0;
    assert(as_memory_lease_data(b,&size)[0]==1 && size==8);
    assert(as_memory_pool_copy(pool,source,9)==nullptr);
    auto *c=as_memory_pool_copy(pool,source,8);
    assert(c && as_memory_pool_copy(pool,source,8)==nullptr);
    ASMemoryStats stats{};
    assert(as_memory_pool_stats(pool,&stats)==1 && stats.live_bytes==16);
    as_memory_lease_release(a);
    assert(as_memory_pool_stats(pool,&stats)==1 && stats.live_bytes==16);
    as_memory_lease_release(b);
    assert(as_memory_pool_stats(pool,&stats)==1 && stats.live_bytes==8);
    as_memory_pool_destroy(pool);
    assert(as_memory_lease_data(c,&size)[7]==8);
    as_memory_lease_release(c);
    return 0;
}
