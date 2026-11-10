#include "include/aerospatial_executor.h"
#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <new>
#include <thread>
#include <vector>
#include <algorithm>

using Clock = std::chrono::steady_clock;
struct ExecutorJob {
    uint64_t id;
    Clock::time_point deadline;
    ASExecutorTask task;
    void *context;
};
struct ASExecutor {
    mutable std::mutex mutex;
    std::condition_variable signal;
    std::deque<ExecutorJob> jobs;
    std::vector<std::thread> workers;
    ASExecutorStats stats{};
    uint32_t capacity=0;
    bool closed=false;
};
namespace {
void run(ASExecutor *q) {
    for (;;) {
        ExecutorJob job{};
        {
            std::unique_lock<std::mutex> guard(q->mutex);
            q->signal.wait(guard,[&]{return q->closed||!q->jobs.empty();});
            if (q->closed && q->jobs.empty()) return;
            job=q->jobs.front();
            q->jobs.pop_front();
            --q->stats.pending;
            if (Clock::now() >= job.deadline) {
                ++q->stats.expired;
                continue;
            }
            ++q->stats.running;
        }
        bool failed=false;
        try { job.task(job.context); } catch (...) { failed=true; }
        {
            std::lock_guard<std::mutex> guard(q->mutex);
            --q->stats.running;
            if (failed) ++q->stats.failed;
            else ++q->stats.completed;
        }
    }
}
}
extern "C" ASExecutor *as_executor_create(uint32_t workers,uint32_t capacity) {
    if (!workers||workers>32||!capacity||capacity>65536) return nullptr;
    auto *q=new(std::nothrow) ASExecutor;
    if (!q) return nullptr;
    q->capacity=capacity;
    try {
        for(uint32_t i=0;i<workers;++i) q->workers.emplace_back(run,q);
    } catch (...) {
        as_executor_shutdown(q);
        delete q;
        return nullptr;
    }
    return q;
}
extern "C" ASExecutorStatus as_executor_submit(ASExecutor *q,uint64_t id,uint32_t deadline_ms,
                                               ASExecutorTask task,void *context) {
    if (!q||!task||!id||!deadline_ms||deadline_ms>600000) return ASEX_INVALID;
    std::lock_guard<std::mutex> guard(q->mutex);
    if (q->closed) return ASEX_CLOSED;
    if (q->jobs.size()>=q->capacity) {++q->stats.rejected;return ASEX_FULL;}
    for(const auto &job:q->jobs) if(job.id==id) return ASEX_INVALID;
    try {
        q->jobs.push_back({id,Clock::now()+std::chrono::milliseconds(deadline_ms),task,context});
    } catch (...) {++q->stats.rejected;return ASEX_FULL;}
    ++q->stats.submitted;
    ++q->stats.pending;
    q->stats.max_pending=std::max(q->stats.max_pending,q->stats.pending);
    q->signal.notify_one();
    return ASEX_OK;
}
extern "C" ASExecutorStatus as_executor_cancel(ASExecutor *q,uint64_t id) {
    if (!q||!id) return ASEX_INVALID;
    std::lock_guard<std::mutex> guard(q->mutex);
    auto it=std::find_if(q->jobs.begin(),q->jobs.end(),[&](const ExecutorJob &job){return job.id==id;});
    if(it==q->jobs.end())return ASEX_NOT_FOUND;
    q->jobs.erase(it);
    --q->stats.pending;
    ++q->stats.cancelled;
    return ASEX_OK;
}
extern "C" int as_executor_stats(const ASExecutor *q,ASExecutorStats *out) {
    if (!q||!out)return 0;
    std::lock_guard<std::mutex> guard(q->mutex);
    *out=q->stats;
    return 1;
}
extern "C" void as_executor_shutdown(ASExecutor *q) {
    if (!q)return;
    {
        std::lock_guard<std::mutex> guard(q->mutex);
        q->closed=true;
        q->stats.cancelled+=q->jobs.size();
        q->jobs.clear();
        q->stats.pending=0;
    }
    q->signal.notify_all();
    for(auto &worker:q->workers) if(worker.joinable())worker.join();
    q->workers.clear();
}
extern "C" void as_executor_destroy(ASExecutor *q) {as_executor_shutdown(q);delete q;}
