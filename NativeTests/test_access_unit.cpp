#include "test_common.h"
#include "../Kernel/include/aerospatial_access_unit.h"
#include <algorithm>
#include <cstdint>
#include <random>
#include <vector>

struct Picture {
    std::vector<uint8_t> avcc, sps, pps;
    uint64_t ordinal = 0;
    bool key = false;
};
static void collect(void *ctx, const ASH264AccessUnit *u) {
    auto &result = *static_cast<std::vector<Picture> *>(ctx);
    result.push_back({std::vector<uint8_t>(u->avcc_bytes, u->avcc_bytes + u->avcc_size),
                      std::vector<uint8_t>(u->sps_bytes, u->sps_bytes + u->sps_size),
                      std::vector<uint8_t>(u->pps_bytes, u->pps_bytes + u->pps_size),
                      u->ordinal, u->keyframe != 0});
}
static void append(std::vector<uint8_t> &out, std::initializer_list<uint8_t> nal) {
    out.insert(out.end(), {0, 0, 0, 1});
    out.insert(out.end(), nal);
}
int main() {
    auto *a = as_h264_access_create(64, 256);
    REQUIRE(a);
    std::vector<uint8_t> sequence;
    append(sequence, {0x67, 0x42, 0, 0x1f});
    append(sequence, {0x68, 0xce, 0x3c});
    append(sequence, {0x65, 0x80, 0x55}); // IDR, first_mb=0
    append(sequence, {0x41, 0x40, 0x55}); // same picture? first_mb=1 (synthetic)
    append(sequence, {0x09, 0xf0});       // AUD boundary
    append(sequence, {0x41, 0x80, 0x66}); // P picture
    append(sequence, {0x09, 0xf0});
    std::vector<Picture> expected;
    REQUIRE(as_h264_access_feed(a, sequence.data(), sequence.size(), collect, &expected) == ASH264_OK);
    REQUIRE(as_h264_access_finish(a, collect, &expected) == ASH264_OK);
    REQUIRE(expected.size() == 2);
    REQUIRE(expected[0].key && !expected[1].key);
    REQUIRE(expected[0].sps.size() == 4 && expected[0].pps.size() == 3);
    REQUIRE(expected[0].avcc.size() == 2 * (4 + 3));
    REQUIRE(expected[0].avcc[3] == 3 && expected[0].avcc[4] == 0x65);
    REQUIRE(expected[0].avcc[10] == 3 && expected[0].avcc[11] == 0x41);
    REQUIRE(expected[1].ordinal == 2);

    // Each prefix/slice may be split at arbitrary callback byte boundaries.
    std::mt19937 gen(1234);
    for (int repeat = 0; repeat < 100; ++repeat) {
        as_h264_access_reset(a);
        std::vector<Picture> actual;
        for (size_t pos = 0; pos < sequence.size();) {
            size_t amount = std::min<size_t>(1 + gen() % 7, sequence.size() - pos);
            REQUIRE(as_h264_access_feed(a, sequence.data() + pos, amount, collect, &actual) == ASH264_OK);
            pos += amount;
        }
        REQUIRE(as_h264_access_finish(a, collect, &actual) == ASH264_OK);
        REQUIRE(actual.size() == 2);
        REQUIRE(actual[0].avcc == expected[0].avcc);
        REQUIRE(actual[1].avcc == expected[1].avcc);
    }
    as_h264_access_reset(a);
    std::vector<Picture> missing_config;
    const uint8_t nonidr[] = {0, 0, 1, 0x41, 0x80, 0, 0, 1, 0x09, 0xf0};
    REQUIRE(as_h264_access_feed(a, nonidr, sizeof(nonidr), collect, &missing_config) == ASH264_OK);
    REQUIRE(as_h264_access_finish(a, collect, &missing_config) == ASH264_OK);
    REQUIRE(missing_config.empty());

    const uint8_t malformed[] = {0, 0, 1, 0x67, 0x64, 0, 0, 1, 0x68, 0x44,
                                 0, 0, 1, 0x65}; // no first_mb bits
    REQUIRE(as_h264_access_feed(a, malformed, sizeof(malformed), collect, &missing_config) == ASH264_OK);
    REQUIRE(as_h264_access_finish(a, collect, &missing_config) == ASH264_INVALID);
    REQUIRE(missing_config.empty());

    // State must be reusable after malformed input. No stale SPS/PPS survives.
    REQUIRE(as_h264_access_feed(a, sequence.data(), sequence.size(), collect, &missing_config) == ASH264_OK);
    REQUIRE(as_h264_access_finish(a, collect, &missing_config) == ASH264_OK);
    REQUIRE(missing_config.size() == 2);
    as_h264_access_destroy(a);
    REQUIRE(as_h264_access_create(0, 16) == nullptr);
    REQUIRE(as_h264_access_create(1024, 1024) == nullptr);
}
