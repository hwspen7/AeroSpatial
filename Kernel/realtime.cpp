#include "include/aerospatial_realtime.h"
#include <atomic>
#include <cmath>
#include <new>
#include <vector>

struct ASRealtimeHeadQueue {
    explicit ASRealtimeHeadQueue(uint32_t capacity) : slots(size_t(capacity) + 1) {}
    std::vector<ASRealtimeHeadSample> slots;
    std::atomic<uint64_t> written{0};
    std::atomic<uint64_t> read{0};
    std::atomic<uint64_t> full{0};
    std::atomic<uint64_t> invalid{0};
    std::atomic<uint64_t> consumed{0};
    std::atomic<uint64_t> coalesced{0};
};

extern "C" ASRealtimeHeadQueue *as_rt_head_create(uint32_t capacity) {
    if (capacity < 2 || capacity > 8192) return nullptr;
    try { return new ASRealtimeHeadQueue(capacity); } catch (...) { return nullptr; }
}
extern "C" void as_rt_head_destroy(ASRealtimeHeadQueue *queue) { delete queue; }
extern "C" ASRealtimeResult as_rt_head_push(ASRealtimeHeadQueue *queue,
                                              ASRealtimeHeadSample sample) {
    if (!queue) return ASRT_INVALID;
    if (!std::isfinite(sample.uptime_seconds) || sample.uptime_seconds < 0 ||
        !std::isfinite(sample.yaw_degrees) || !std::isfinite(sample.pitch_degrees) ||
        !std::isfinite(sample.roll_degrees) ||
        !std::isfinite(sample.received_host_seconds) || sample.received_host_seconds < 0) {
        queue->invalid.fetch_add(1, std::memory_order_relaxed);
        return ASRT_INVALID;
    }
    const uint64_t head = queue->written.load(std::memory_order_relaxed);
    if (head - queue->read.load(std::memory_order_acquire) >= queue->slots.size() - 1) {
        queue->full.fetch_add(1, std::memory_order_relaxed);
        return ASRT_FULL;
    }
    queue->slots[head % queue->slots.size()] = sample;
    queue->written.store(head + 1, std::memory_order_release);
    return ASRT_OK;
}
extern "C" ASRealtimeResult as_rt_head_pop(ASRealtimeHeadQueue *queue,
                                             ASRealtimeHeadSample *sample) {
    if (!queue || !sample) return ASRT_INVALID;
    const uint64_t tail = queue->read.load(std::memory_order_relaxed);
    if (queue->written.load(std::memory_order_acquire) == tail) return ASRT_EMPTY;
    *sample = queue->slots[tail % queue->slots.size()];
    queue->read.store(tail + 1, std::memory_order_release);
    queue->consumed.fetch_add(1, std::memory_order_relaxed);
    return ASRT_OK;
}
extern "C" ASRealtimeResult as_rt_head_pop_latest(ASRealtimeHeadQueue *queue,
                                                    ASRealtimeHeadSample *sample) {
    if (!queue || !sample) return ASRT_INVALID;
    const uint64_t tail = queue->read.load(std::memory_order_relaxed);
    const uint64_t limit = queue->written.load(std::memory_order_acquire);
    if (tail == limit) return ASRT_EMPTY;
    // Snapshot a finite suffix once. A busy producer must never starve a UI read.
    // Producer cannot replace the last slot before we advance read.
    *sample = queue->slots[(limit - 1) % queue->slots.size()];
    queue->read.store(limit, std::memory_order_release);
    const uint64_t count = limit - tail;
    queue->consumed.fetch_add(count, std::memory_order_relaxed);
    queue->coalesced.fetch_add(count - 1, std::memory_order_relaxed);
    return ASRT_OK;
}
extern "C" ASRealtimeResult as_rt_head_stats(const ASRealtimeHeadQueue *queue,
                                               ASRealtimeQueueStats *stats) {
    if (!queue || !stats) return ASRT_INVALID;
    stats->accepted = queue->written.load(std::memory_order_acquire);
    stats->rejected_full = queue->full.load(std::memory_order_relaxed);
    stats->rejected_invalid = queue->invalid.load(std::memory_order_relaxed);
    stats->consumed = queue->consumed.load(std::memory_order_relaxed);
    stats->coalesced = queue->coalesced.load(std::memory_order_relaxed);
    return ASRT_OK;
}
