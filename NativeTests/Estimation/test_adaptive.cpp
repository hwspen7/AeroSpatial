#include "test_common.h"
#include "../Kernel/include/aerospatial_adaptive.h"
#include <cmath>
#include <limits>

int main() {
    ASAdaptiveState governor{};
    uint32_t quality = 99;
    REQUIRE(as_adaptive_update(&governor, 1000000000, 0, 0, 3, 10, &quality) == AS_OK);
    REQUIRE(quality == 0);
    REQUIRE(as_adaptive_update(&governor, 1100000000, 900, 2, 30, 10, &quality) == AS_OK);
    REQUIRE(quality == 2);
    REQUIRE(as_adaptive_update(&governor, 1200000000, 970, 3, 31, 10, &quality) == AS_OK);
    REQUIRE(quality == 3);
    for (int i=0; i<5; ++i) {
        REQUIRE(as_adaptive_update(&governor, 1500000000ULL+(uint64_t)i*300000000ULL,
                                   100, 0, 2, 10, &quality) == AS_OK);
    }
    REQUIRE(quality < 3 && quality >= 1);
    REQUIRE(quality < 3 && quality >= 1);
    const uint32_t before = governor.quality;
    REQUIRE(as_adaptive_update(&governor, 1000000000, 0, 0, 2, 10, &quality) != AS_OK);
    REQUIRE(governor.quality == before);
    REQUIRE(as_adaptive_update(&governor, 4000000000ULL, 1001, 0, 2, 10, &quality) != AS_OK);
    REQUIRE(as_adaptive_update(&governor, 4000000000ULL, 1, 0,
                               std::numeric_limits<double>::quiet_NaN(), 10, &quality) != AS_OK);
    // A 30Hz healthy stream must eventually recover: elapsed time is measured
    // from a quality change, not from the immediately preceding observation.
    ASAdaptiveState fast{};
    REQUIRE(as_adaptive_update(&fast, 1000000000ULL, 0, 0, 1, 10, &quality) == AS_OK);
    REQUIRE(as_adaptive_update(&fast, 1100000000ULL, 970, 3, 40, 10, &quality) == AS_OK);
    REQUIRE(quality == 2);
    for (int i=1;i<=50;++i) REQUIRE(as_adaptive_update(&fast,
        1100000000ULL + (uint64_t)i*33000000ULL, 10, 0, 1, 10, &quality) == AS_OK);
    REQUIRE(quality == 0);
    ASHeadIntentState intent{};
    ASHeadIntentPrediction prediction{};
    REQUIRE(as_head_intent_predict(&intent, 1, 179, 0, 0.1, &prediction) == AS_OK);
    REQUIRE(std::abs(prediction.predicted_yaw_deg-179)<1e-8);
    REQUIRE(as_head_intent_predict(&intent, 1.1, -179, 5, 0.1, &prediction) == AS_OK);
    REQUIRE(prediction.yaw_rate_deg_s > 0 && prediction.yaw_rate_deg_s < 60);
    REQUIRE(prediction.predicted_yaw_deg > -180 && prediction.predicted_yaw_deg < 180);
    REQUIRE(as_head_intent_predict(&intent, 1.1, 15, 0, 0.1, &prediction) != AS_OK);
    const double ts = intent.timestamp_seconds;
    REQUIRE(as_head_intent_predict(&intent, 1.105, 150, 0, 0.1, &prediction) == AS_OUTLIER_REJECTED);
    REQUIRE(intent.timestamp_seconds == ts);
    REQUIRE(as_head_intent_predict(&intent, 3, 12, -7, 0.1, &prediction) == AS_OK);
    REQUIRE(prediction.yaw_rate_deg_s == 0);
    REQUIRE(as_head_intent_predict(&intent, 4, 12, 0, 1, &prediction) == AS_INVALID_ARGUMENT);
}
