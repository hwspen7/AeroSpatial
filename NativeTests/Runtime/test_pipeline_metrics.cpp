#include "test_common.h"
#include "aerospatial_runtime.h"
#include <thread>
#include <vector>
int main() {
    const uint64_t limits[AS_PIPELINE_STAGE_COUNT] = {100, 200, 300, 400, 500};
    REQUIRE(as_pipeline_metrics_create(nullptr) == nullptr);
    auto *m = as_pipeline_metrics_create(limits);
    REQUIRE(m);
    REQUIRE(!as_pipeline_metrics_record(m, AS_PIPELINE_INGRESS, 2, 1));
    REQUIRE(!as_pipeline_metrics_record(m, AS_PIPELINE_STAGE_COUNT, 0, 3));
    REQUIRE(as_pipeline_metrics_record(m, AS_PIPELINE_INGRESS, 10, 90));
    REQUIRE(as_pipeline_metrics_record(m, AS_PIPELINE_INGRESS, 10, 210));
    REQUIRE(as_pipeline_metrics_record(m, AS_PIPELINE_END_TO_END, 0, 700));
    ASRuntimeReport report{};
    REQUIRE(as_pipeline_metrics_report(m, AS_PIPELINE_INGRESS, &report));
    REQUIRE(report.samples == 2 && report.breaches == 1);
    REQUIRE(report.maximum_ns == 200 && report.p99_upper_ns >= 200);
    REQUIRE(as_pipeline_metrics_report(m, AS_PIPELINE_END_TO_END, &report));
    REQUIRE(report.samples == 1 && report.breaches == 1);
    std::vector<std::thread> writers;
    for (int n = 0; n < 4; ++n) writers.emplace_back([&] {
        for (int i = 0; i < 20000; ++i)
            REQUIRE(as_pipeline_metrics_record(m, AS_PIPELINE_QUEUE, 100, 150));
    });
    for (auto &thread : writers) thread.join();
    REQUIRE(as_pipeline_metrics_report(m, AS_PIPELINE_QUEUE, &report));
    REQUIRE(report.samples == 80000 && report.breaches == 0);
    as_pipeline_metrics_reset(m);
    REQUIRE(as_pipeline_metrics_report(m, AS_PIPELINE_QUEUE, &report) &&
            report.samples == 0);
    as_pipeline_metrics_destroy(m);
}
