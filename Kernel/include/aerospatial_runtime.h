#ifndef AEROSPATIAL_RUNTIME_H
#define AEROSPATIAL_RUNTIME_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ASRuntimeMetrics ASRuntimeMetrics;
typedef struct {
    uint64_t samples;
    uint64_t breaches;
    uint64_t maximum_ns;
    uint64_t p95_upper_ns;
    uint64_t p99_upper_ns;
} ASRuntimeReport;

/// All operations are fixed-memory and thread-safe; a report is a concurrent snapshot.
ASRuntimeMetrics *as_runtime_metrics_create(uint64_t deadline_ns);
void as_runtime_metrics_destroy(ASRuntimeMetrics *metrics);
int as_runtime_metrics_record(ASRuntimeMetrics *metrics, uint64_t duration_ns);
int as_runtime_metrics_report(const ASRuntimeMetrics *metrics, ASRuntimeReport *report);
void as_runtime_metrics_reset(ASRuntimeMetrics *metrics);
#ifdef __cplusplus
}
#endif
#endif
