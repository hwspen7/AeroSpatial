#include "include/aerospatial_runtime.h"
#include <array>
#include <new>

struct ASPipelineMetrics {
    std::array<ASRuntimeMetrics *, AS_PIPELINE_STAGE_COUNT> stages{};
    ~ASPipelineMetrics() { for (auto *stage : stages) as_runtime_metrics_destroy(stage); }
};
extern "C" ASPipelineMetrics *as_pipeline_metrics_create(
    const uint64_t deadlines[AS_PIPELINE_STAGE_COUNT]) {
    if (!deadlines) return nullptr;
    auto *m = new (std::nothrow) ASPipelineMetrics();
    if (!m) return nullptr;
    for (uint32_t i = 0; i < AS_PIPELINE_STAGE_COUNT; ++i) {
        m->stages[i] = as_runtime_metrics_create(deadlines[i]);
        if (!m->stages[i]) { delete m; return nullptr; }
    }
    return m;
}
extern "C" void as_pipeline_metrics_destroy(ASPipelineMetrics *m) { delete m; }
extern "C" int as_pipeline_metrics_record(ASPipelineMetrics *m, uint32_t stage,
                                           uint64_t begin_ns, uint64_t end_ns) {
    if (!m || stage >= AS_PIPELINE_STAGE_COUNT || end_ns < begin_ns) return 0;
    return as_runtime_metrics_record(m->stages[stage], end_ns - begin_ns);
}
extern "C" int as_pipeline_metrics_report(const ASPipelineMetrics *m, uint32_t stage,
                                           ASRuntimeReport *out) {
    if (!m || stage >= AS_PIPELINE_STAGE_COUNT) return 0;
    return as_runtime_metrics_report(m->stages[stage], out);
}
extern "C" void as_pipeline_metrics_reset(ASPipelineMetrics *m) {
    if (!m) return;
    for (auto *stage : m->stages) as_runtime_metrics_reset(stage);
}
