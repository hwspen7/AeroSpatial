#ifndef AEROSPATIAL_WORK_QUEUE_H
#define AEROSPATIAL_WORK_QUEUE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ASWorkQueue ASWorkQueue;
typedef enum { ASWQ_OK = 0, ASWQ_EMPTY = 1, ASWQ_EXPIRED = 2,
               ASWQ_FULL = 3, ASWQ_CLOSED = 4, ASWQ_INVALID = 5 } ASWorkStatus;
typedef enum { ASWQ_ESSENTIAL = 0, ASWQ_OPTIONAL = 1 } ASWorkPriority;
typedef struct {
    uint64_t trace_id;
    uint64_t received_ns;
    uint64_t deadline_ns; // Absolute monotonic deadline in same domain as now_ns.
    uint32_t kind;
    uint32_t priority;
} ASWorkHeader;
typedef struct {
    uint64_t accepted;
    uint64_t completed;
    uint64_t rejected;
    uint64_t evicted_optional;
    uint64_t expired;
    uint64_t queue_bytes;
    uint64_t high_water_bytes;
    uint64_t queue_events;
    uint64_t high_water_events;
    uint64_t maximum_queue_wait_ns;
} ASWorkStats;

/// Copies bounded metadata payloads into a synchronized native queue.
/// Never use this best-effort task queue for aircraft control or safety authority.
/// Essential entries may evict optional entries; no essential entry is overwritten.
ASWorkQueue *as_work_queue_create(size_t maximum_events, size_t maximum_bytes,
                                  size_t maximum_payload_bytes);
void as_work_queue_destroy(ASWorkQueue *queue);
void as_work_queue_close(ASWorkQueue *queue);
ASWorkStatus as_work_queue_push(ASWorkQueue *queue, ASWorkHeader header,
                                 const uint8_t *data, size_t length, uint64_t now_ns);
/// Returns ASWQ_INVALID without removing an item if the destination is too small.
/// Expired entries are discarded and counted, then the next valid item is returned.
ASWorkStatus as_work_queue_pop(ASWorkQueue *queue, uint64_t now_ns, ASWorkHeader *header,
                                uint8_t *buffer, size_t capacity, size_t *length);
int as_work_queue_stats(const ASWorkQueue *queue, ASWorkStats *out);
#ifdef __cplusplus
}
#endif
#endif
