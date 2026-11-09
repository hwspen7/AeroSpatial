#include "test_common.h"
#include "../Kernel/include/aerospatial_runtime.h"
#include <atomic>
#include <thread>
#include <vector>

int main() {
    REQUIRE(as_runtime_metrics_create(0) == nullptr);
    auto *metrics = as_runtime_metrics_create(100);
    REQUIRE(metrics);
    REQUIRE(!as_runtime_metrics_record(nullptr, 1));
    for (auto sample : {uint64_t{1}, uint64_t{2}, uint64_t{100}, uint64_t{200}})
        REQUIRE(as_runtime_metrics_record(metrics, sample));
    ASRuntimeReport report{};
    REQUIRE(as_runtime_metrics_report(metrics, &report));
    REQUIRE(report.samples == 4 && report.breaches == 1 && report.maximum_ns == 200);
    REQUIRE(report.p95_upper_ns >= 200 && report.p99_upper_ns >= 200);
    as_runtime_metrics_reset(metrics);
    REQUIRE(as_runtime_metrics_report(metrics, &report) && report.samples == 0);
    std::vector<std::thread> writers;
    for (int i = 0; i < 4; ++i) writers.emplace_back([=] {
        for (int k = 0; k < 10000; ++k) REQUIRE(as_runtime_metrics_record(metrics, uint64_t(k + 1)));
    });
    for (auto &thread : writers) thread.join();
    REQUIRE(as_runtime_metrics_report(metrics, &report));
    REQUIRE(report.samples == 40000 && report.maximum_ns == 10000);
    REQUIRE(report.breaches == 39600);
    as_runtime_metrics_destroy(metrics);
}
