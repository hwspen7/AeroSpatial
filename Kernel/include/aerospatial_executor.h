#ifndef AEROSPATIAL_EXECUTOR_H
#define AEROSPATIAL_EXECUTOR_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ASExecutor ASExecutor;
typedef void (*ASExecutorTask)(void *context);
typedef enum { ASEX_OK=0, ASEX_FULL=1, ASEX_CLOSED=2, ASEX_INVALID=3,
               ASEX_NOT_FOUND=4 } ASExecutorStatus;
typedef struct {
    uint64_t submitted, completed, failed, expired, cancelled, rejected;
    uint64_t pending, running, max_pending;
} ASExecutorStats;

/// Trusted, optional CPU work only; never call flight authorization/actuators.
/// Deadline is relative milliseconds from submission. No real-time guarantees.
/// The caller owns context until callback completion OR explicit cancellation
/// successfully removes the pending task. Shutdown waits for running callbacks.
ASExecutor *as_executor_create(uint32_t worker_count, uint32_t max_pending);
ASExecutorStatus as_executor_submit(ASExecutor *executor, uint64_t id,
                uint32_t deadline_ms, ASExecutorTask task, void *context);
ASExecutorStatus as_executor_cancel(ASExecutor *executor, uint64_t id);
int as_executor_stats(const ASExecutor *executor, ASExecutorStats *stats);
void as_executor_shutdown(ASExecutor *executor);
void as_executor_destroy(ASExecutor *executor);
#ifdef __cplusplus
}
#endif
#endif
