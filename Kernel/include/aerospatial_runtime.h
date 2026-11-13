#ifndef AEROSPATIAL_RUNTIME_H
#define AEROSPATIAL_RUNTIME_H
#include <stdint.h>
#include <stddef.h>
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

/* C ABI v1.1: callers must negotiate a major version before using extensions. */
enum {
    AS_NATIVE_FEATURE_RESOURCE_BUDGET = 1u << 0,
    AS_NATIVE_FEATURE_CLOCK_QUALITY = 1u << 1,
    AS_NATIVE_FEATURE_PIPELINE_METRICS = 1u << 2,
    AS_NATIVE_FEATURE_COVARIANCE_DIAGNOSTICS = 1u << 3
};
typedef struct {
    uint32_t struct_size;
    uint32_t major;
    uint32_t minor;
    uint32_t reserved;
    uint64_t feature_bits;
} ASNativeAbiInfo;
/* Returns zero if the caller's buffer is shorter than the v1 structure. */
int as_native_abi_info(ASNativeAbiInfo *out, size_t capacity);

enum { AS_RESOURCE_BUS = 0, AS_RESOURCE_POOL = 1,
       AS_RESOURCE_WORK = 2, AS_RESOURCE_VIDEO = 3,
       AS_RESOURCE_CLASS_COUNT = 4 };
typedef struct ASResourceGovernor ASResourceGovernor;
typedef struct ASResourcePermit ASResourcePermit;
typedef struct {
    uint64_t limit_bytes;
    uint64_t live_bytes;
    uint64_t high_water_bytes;
    uint64_t by_class_bytes[AS_RESOURCE_CLASS_COUNT];
    uint64_t rejected;
} ASResourceReport;
/* Opt-in cross-component payload budget. Retained permits outlive their governor
   handles, so external leases remain charged through pool/bus/queue shutdown. */
ASResourceGovernor *as_resource_governor_create(uint64_t limit_bytes);
ASResourceGovernor *as_resource_governor_retain(const ASResourceGovernor *governor);
void as_resource_governor_destroy(ASResourceGovernor *governor);
ASResourcePermit *as_resource_permit_acquire(ASResourceGovernor *governor,
                                             uint32_t resource_class, uint64_t bytes);
void as_resource_permit_release(ASResourcePermit *permit);
int as_resource_governor_report(const ASResourceGovernor *governor, ASResourceReport *out);

enum {
    AS_CLOCK_ACCEPTED = 0, AS_CLOCK_INVALID = 1, AS_CLOCK_REGRESSION = 2,
    AS_CLOCK_STALE = 3, AS_CLOCK_UNCERTAIN = 4, AS_CLOCK_JUMP = 5
};
enum { AS_CLOCK_AIRPODS = 1, AS_CLOCK_IPHONE = 2, AS_CLOCK_AIRCRAFT = 3 };
typedef struct ASClockQuality ASClockQuality;
typedef struct {
    uint64_t accepted;
    uint64_t rejected;
    uint64_t last_age_ns;
    uint64_t last_uncertainty_ns;
    uint32_t has_anchor;
} ASClockReport;
/* source_ns is in its declared clock domain. mapped_ns is an independently
   established conversion into the arrival/reference monotonic clock domain.
   This function NEVER estimates a clock offset or silently translates domains. */
ASClockQuality *as_clock_quality_create(uint64_t max_age_ns,
                                        uint64_t max_uncertainty_ns, uint64_t max_jump_ns);
void as_clock_quality_destroy(ASClockQuality *quality);
int as_clock_quality_observe(ASClockQuality *quality, uint32_t domain,
                             uint64_t source_ns, uint64_t mapped_ns,
                             uint64_t arrival_ns, uint64_t uncertainty_ns,
                             ASClockReport *out);
int as_clock_quality_reset(ASClockQuality *quality, uint32_t domain);

enum { AS_PIPELINE_INGRESS = 0, AS_PIPELINE_QUEUE = 1,
       AS_PIPELINE_DECODE = 2, AS_PIPELINE_ALGORITHM = 3,
       AS_PIPELINE_END_TO_END = 4, AS_PIPELINE_STAGE_COUNT = 5 };
typedef struct ASPipelineMetrics ASPipelineMetrics;
/* All start/end pairs must share one monotonic clock domain; all end >= start.
   Reports use the same conservative logarithmic percentile upper bounds as
   ASRuntimeReport, not exact quantiles. Reset requires producer quiescence. */
ASPipelineMetrics *as_pipeline_metrics_create(const uint64_t deadlines_ns[AS_PIPELINE_STAGE_COUNT]);
void as_pipeline_metrics_destroy(ASPipelineMetrics *metrics);
int as_pipeline_metrics_record(ASPipelineMetrics *metrics, uint32_t stage,
                               uint64_t begin_ns, uint64_t end_ns);
int as_pipeline_metrics_report(const ASPipelineMetrics *metrics, uint32_t stage,
                               ASRuntimeReport *out);
void as_pipeline_metrics_reset(ASPipelineMetrics *metrics);

#ifdef __cplusplus
}
#endif
#endif
