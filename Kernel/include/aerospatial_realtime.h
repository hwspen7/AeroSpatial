#ifndef AEROSPATIAL_REALTIME_H
#define AEROSPATIAL_REALTIME_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ASRealtimeHeadQueue ASRealtimeHeadQueue;
typedef struct {
    double uptime_seconds;
    double yaw_degrees;
    double pitch_degrees;
    double roll_degrees;
    double received_host_seconds;
} ASRealtimeHeadSample;
typedef struct {
    uint64_t accepted;
    uint64_t rejected_full;
    uint64_t rejected_invalid;
    uint64_t consumed;
    uint64_t coalesced;
} ASRealtimeQueueStats;
typedef enum {
    ASRT_OK = 0,
    ASRT_EMPTY = 1,
    ASRT_FULL = 2,
    ASRT_INVALID = 3
} ASRealtimeResult;

/* Single producer and single consumer. Calls never allocate after create.
   Both caller threads must stop before destroy. No disk, UI or flight output. */
ASRealtimeHeadQueue *as_rt_head_create(uint32_t capacity);
void as_rt_head_destroy(ASRealtimeHeadQueue *queue);
ASRealtimeResult as_rt_head_push(ASRealtimeHeadQueue *queue, ASRealtimeHeadSample sample);
ASRealtimeResult as_rt_head_pop(ASRealtimeHeadQueue *queue, ASRealtimeHeadSample *sample);
/* Discards intermediate samples for display/preview only, never command authorization. */
ASRealtimeResult as_rt_head_pop_latest(ASRealtimeHeadQueue *queue, ASRealtimeHeadSample *sample);
ASRealtimeResult as_rt_head_stats(const ASRealtimeHeadQueue *queue, ASRealtimeQueueStats *stats);
#ifdef __cplusplus
}
#endif
#endif
