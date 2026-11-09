#include "test_common.h"
#include "../Kernel/include/aerospatial_qos.h"
#include <atomic>
#include <cmath>
#include <cstdint>
#include <thread>
#include <vector>

static void rate_and_pressure() {
    auto *q = as_qos_create();
    REQUIRE(q);
    REQUIRE(as_qos_configure(q, {3, 20.0, 4.0, 700}) == ASQOS_ADMITTED);
    REQUIRE(as_qos_admit(q, 3, 0, 3, 0) == ASQOS_ADMITTED);
    REQUIRE(as_qos_admit(q, 3, 0, 2, 0) == ASQOS_RATE_LIMITED);
    REQUIRE(as_qos_admit(q, 3, 50000000, 2, 800) == ASQOS_BACKLOGGED);
    REQUIRE(as_qos_admit(q, 3, 100000000, 2, 0) == ASQOS_ADMITTED);
    REQUIRE(as_qos_admit(q, 3, 99999999, 1, 0) == ASQOS_TIME_REGRESSION);
    REQUIRE(as_qos_admit(q, 3, 200000000, NAN, 0) == ASQOS_INVALID);
    ASQosStats s{};
    REQUIRE(as_qos_stats(q, 3, &s) == ASQOS_ADMITTED);
    REQUIRE(s.seen == 6 && s.admitted == 2 && s.rate_limited == 1);
    REQUIRE(s.backlogged == 1 && s.invalid == 2);
    REQUIRE(std::abs(s.available_units - 1.0) < 1e-9);
    as_qos_destroy(q);
}
static void validation_and_isolation() {
    auto *q = as_qos_create();
    REQUIRE(as_qos_configure(q, {6, 10, 10, 900}) == ASQOS_INVALID);
    REQUIRE(as_qos_configure(q, {1, 10, 10, 900}) == ASQOS_INVALID);
    REQUIRE(as_qos_configure(q, {2, 10, 10, 900}) == ASQOS_INVALID);
    REQUIRE(as_qos_configure(q, {1, 0, 10, 900}) == ASQOS_INVALID);
    REQUIRE(as_qos_configure(q, {1, 10, INFINITY, 900}) == ASQOS_INVALID);
    REQUIRE(as_qos_configure(q, {1, 10, 10, 1001}) == ASQOS_INVALID);
    REQUIRE(as_qos_admit(q, 2, 10, 1, 0) == ASQOS_INVALID);
    REQUIRE(as_qos_configure(q, {3, 1, 1, 1000}) == ASQOS_ADMITTED);
    REQUIRE(as_qos_configure(q, {4, 1, 1, 1000}) == ASQOS_ADMITTED);
    REQUIRE(as_qos_admit(q, 3, 1, 1, 0) == ASQOS_ADMITTED);
    REQUIRE(as_qos_admit(q, 3, 1, 1, 0) == ASQOS_RATE_LIMITED);
    REQUIRE(as_qos_admit(q, 4, 1, 1, 0) == ASQOS_ADMITTED);
    REQUIRE(as_qos_configure(q, {3, 1, 1, 1000}) == ASQOS_ADMITTED);
    REQUIRE(as_qos_admit(q, 3, 1, 1, 0) == ASQOS_ADMITTED);
    as_qos_destroy(q);
}
static void concurrent_admission() {
    auto *q = as_qos_create();
    REQUIRE(as_qos_configure(q, {4, 1, 2000, 1000}) == ASQOS_ADMITTED);
    std::atomic<int> accepted{0};
    std::vector<std::thread> threads;
    for (int i = 0; i < 8; ++i) threads.emplace_back([&]() {
        for (int j = 0; j < 1000; ++j) {
            auto status = as_qos_admit(q, 4, 0, 1, 0);
            REQUIRE(status == ASQOS_ADMITTED || status == ASQOS_RATE_LIMITED);
            if (status == ASQOS_ADMITTED) ++accepted;
        }
    });
    for (auto &thread : threads) thread.join();
    REQUIRE(accepted == 2000);
    ASQosStats stats{};
    REQUIRE(as_qos_stats(q, 4, &stats) == ASQOS_ADMITTED);
    REQUIRE(stats.seen == 8000 && stats.admitted == 2000 && stats.rate_limited == 6000);
    as_qos_destroy(q);
}
int main() {
    rate_and_pressure();
    validation_and_isolation();
    concurrent_admission();
}
