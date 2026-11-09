#ifndef AEROSPATIAL_QOS_H
#define AEROSPATIAL_QOS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Discretionary compute admission only. Never gate aircraft failsafes or commands. */
typedef struct ASQosGovernor ASQosGovernor;

typedef enum {
    ASQOS_ADMITTED = 0,
    ASQOS_RATE_LIMITED = 1,
    ASQOS_BACKLOGGED = 2,
    ASQOS_INVALID = 3,
    ASQOS_TIME_REGRESSION = 4
} ASQosDecision;

typedef struct {
    uint32_t stream_id;              /* 3..5 only: video/perception/diagnostic */
    double refill_units_per_second; /* measured/estimated units of computation */
    double burst_units;
    uint32_t maximum_pressure_permille;  /* 0..1000 */
} ASQosPolicy;

typedef struct {
    uint64_t seen;
    uint64_t admitted;
    uint64_t rate_limited;
    uint64_t backlogged;
    uint64_t invalid;
    double available_units;
} ASQosStats;

/* Fixed-size stream table. No heap allocations on the admission hot path.
   Handles may be used from multiple threads; do not destroy during use. */
ASQosGovernor *as_qos_create(void);
void as_qos_destroy(ASQosGovernor *governor);
/* Reconfiguration clears this stream's counters and restores its burst capacity. */
ASQosDecision as_qos_configure(ASQosGovernor *governor, ASQosPolicy policy);
/* Source timestamp MUST be monotonic within each stream's chosen clock domain.
   Pressure 1000 is fully saturated; 0 indicates no observed backlog.
   Rejecting work never enqueues, delays or retries the caller. */
ASQosDecision as_qos_admit(ASQosGovernor *governor, uint32_t stream_id,
                           uint64_t timestamp_ns, double estimated_units,
                           uint32_t pressure_permille);
ASQosDecision as_qos_stats(ASQosGovernor *governor, uint32_t stream_id,
                           ASQosStats *result);

#ifdef __cplusplus
}
#endif
#endif
