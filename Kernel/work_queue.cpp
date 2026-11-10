#include "include/aerospatial_work_queue.h"
#include <algorithm>
#include <deque>
#include <mutex>
#include <new>
#include <vector>

struct WorkItem { ASWorkHeader header; std::vector<uint8_t> payload; uint64_t enqueued; };
struct ASWorkQueue {
    explicit ASWorkQueue(size_t count, size_t memory, size_t payload)
      : max_events(count), max_bytes(memory), max_payload(payload) {}
    mutable std::mutex lock;
    const size_t max_events, max_bytes, max_payload;
    std::deque<WorkItem> essential, optional;
    ASWorkStats stats{};
    bool closed = false;
};
namespace {
bool is_full(const ASWorkQueue &q, size_t additional) {
    return q.stats.queue_events >= q.max_events ||
           additional > q.max_bytes - q.stats.queue_bytes;
}
void discard_front(ASWorkQueue &q, std::deque<WorkItem> &lane) {
    q.stats.queue_bytes -= lane.front().payload.size();
    --q.stats.queue_events;
    lane.pop_front();
}
}
extern "C" ASWorkQueue *as_work_queue_create(size_t count, size_t bytes, size_t payload) {
    if (!count || count > 65536 || !bytes || bytes > (512u << 20) ||
        !payload || payload > bytes || payload > (8u << 20)) return nullptr;
    return new (std::nothrow) ASWorkQueue(count, bytes, payload);
}
extern "C" void as_work_queue_destroy(ASWorkQueue *q) { delete q; }
extern "C" void as_work_queue_close(ASWorkQueue *q) {
    if (!q) return;
    std::lock_guard<std::mutex> lock(q->lock);
    q->closed = true;
    q->essential.clear();
    q->optional.clear();
    q->stats.queue_events = 0;
    q->stats.queue_bytes = 0;
}
extern "C" ASWorkStatus as_work_queue_push(ASWorkQueue *q, ASWorkHeader h,
                                            const uint8_t *data, size_t n, uint64_t now) {
    if (!q || (!data && n)) return ASWQ_INVALID;
    std::lock_guard<std::mutex> lock(q->lock);
    if (q->closed) return ASWQ_CLOSED;
    if ((h.priority != ASWQ_ESSENTIAL && h.priority != ASWQ_OPTIONAL) ||
        !h.deadline_ns || h.received_ns > now || h.deadline_ns <= h.received_ns ||
        n > q->max_payload || n > q->max_bytes) {
        ++q->stats.rejected;
        return ASWQ_INVALID;
    }
    if (now >= h.deadline_ns) { ++q->stats.expired; return ASWQ_EXPIRED; }
    // Reject without mutation on allocation failure; never overwrite essential.
    WorkItem item;
    item.header = h;
    item.enqueued = now;
    try { if (n) item.payload.assign(data, data + n); }
    catch (...) { ++q->stats.rejected; return ASWQ_FULL; }
    // Optional work must not displace existing work. Essential work may evict optional.
    if (h.priority == ASWQ_ESSENTIAL) {
        while (is_full(*q, n) && !q->optional.empty()) {
            discard_front(*q, q->optional);
            ++q->stats.evicted_optional;
        }
    }
    if (is_full(*q, n)) { ++q->stats.rejected; return ASWQ_FULL; }
    try {
        if (h.priority == ASWQ_ESSENTIAL) q->essential.push_back(std::move(item));
        else q->optional.push_back(std::move(item));
    } catch (...) { ++q->stats.rejected; return ASWQ_FULL; }
    ++q->stats.accepted;
    ++q->stats.queue_events;
    q->stats.queue_bytes += n;
    q->stats.high_water_bytes = std::max(q->stats.high_water_bytes, q->stats.queue_bytes);
    q->stats.high_water_events = std::max(q->stats.high_water_events, q->stats.queue_events);
    return ASWQ_OK;
}
extern "C" ASWorkStatus as_work_queue_pop(ASWorkQueue *q, uint64_t now, ASWorkHeader *h,
                                           uint8_t *out, size_t capacity, size_t *length) {
    if (!q || !h || !length || (!out && capacity)) return ASWQ_INVALID;
    std::lock_guard<std::mutex> lock(q->lock);
    for (;;) {
        auto &lane = !q->essential.empty() ? q->essential : q->optional;
        if (lane.empty()) return q->closed ? ASWQ_CLOSED : ASWQ_EMPTY;
        const auto &front = lane.front();
        if (now < front.enqueued) return ASWQ_INVALID;
        if (now >= front.header.deadline_ns) {
            discard_front(*q, lane);
            ++q->stats.expired;
            continue;
        }
        *length = front.payload.size();
        if (capacity < *length || (!out && *length)) return ASWQ_INVALID;
        *h = front.header;
        if (*length) std::copy(front.payload.begin(), front.payload.end(), out);
        q->stats.maximum_queue_wait_ns = std::max(q->stats.maximum_queue_wait_ns,
                                                   now - front.enqueued);
        discard_front(*q, lane);
        ++q->stats.completed;
        return ASWQ_OK;
    }
}
extern "C" int as_work_queue_stats(const ASWorkQueue *q, ASWorkStats *out) {
    if (!q || !out) return 0;
    std::lock_guard<std::mutex> lock(q->lock);
    *out = q->stats;
    return 1;
}
