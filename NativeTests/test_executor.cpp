#include "../Kernel/include/aerospatial_executor.h"
#include <atomic>
#include <cassert>
#include <chrono>
#include <thread>
static void count(void *p){++*static_cast<std::atomic<int>*>(p);}
int main() {
    assert(as_executor_create(0,1)==nullptr);
    auto *q=as_executor_create(2,1024);
    assert(q);
    std::atomic<int> count_done{0};
    for(uint64_t i=1;i<=100;++i)
        assert(as_executor_submit(q,i,10000,count,&count_done)==ASEX_OK);
    as_executor_shutdown(q);
    ASExecutorStats stats{};
    assert(as_executor_stats(q,&stats)==1);
    assert(stats.completed+stats.cancelled==100);
    assert(stats.failed==0 && stats.running==0 && stats.pending==0);
    assert(count_done.load()==static_cast<int>(stats.completed));
    assert(as_executor_submit(q,200,500,count,&count_done)==ASEX_CLOSED);
    as_executor_destroy(q);
    // Another independent instance validates callback completion and reentrance.
    q=as_executor_create(1,2);
    assert(as_executor_submit(q,1,2000,count,&count_done)==ASEX_OK);
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    as_executor_shutdown(q);
    assert(as_executor_stats(q,&stats)==1 && stats.completed==1);
    as_executor_destroy(q);
}
