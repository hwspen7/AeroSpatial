#include "test_common.h"
#include "../Kernel/include/aerospatial_h264.h"
#include <cstdint>
#include <vector>
#include <random>

struct Unit { uint8_t type; std::vector<uint8_t> bytes; };
static void collect(void *ctx, const uint8_t *data, size_t size, uint8_t type) {
    auto &units = *static_cast<std::vector<Unit> *>(ctx);
    units.push_back({type, std::vector<uint8_t>(data, data + size)});
}

int main() {
    auto *parser = as_h264_create(64);
    REQUIRE(parser);
    std::vector<Unit> units;
    const uint8_t a[] = {0, 0, 0};
    const uint8_t b[] = {1, 0x67, 0x42, 0, 0};
    const uint8_t c[] = {0, 1, 0x68, 0xce, 0, 0, 1, 0x65, 0x88};
    REQUIRE(as_h264_feed(parser, a, sizeof(a), collect, &units) == ASH264_OK);
    REQUIRE(as_h264_feed(parser, b, sizeof(b), collect, &units) == ASH264_OK);
    REQUIRE(as_h264_feed(parser, c, sizeof(c), collect, &units) == ASH264_OK);
    REQUIRE(units.size() == 2);
    REQUIRE(units[0].type == 7 && units[0].bytes.size() == 2);
    REQUIRE(units[1].type == 8 && units[1].bytes.size() == 2);
    REQUIRE(as_h264_finish(parser, collect, &units) == ASH264_OK);
    REQUIRE(units.size() == 3 && units[2].type == 5);

    const uint8_t invalid[] = {0, 0, 1, 0x80, 0x44, 0, 0, 1, 0x67};
    REQUIRE(as_h264_feed(parser, invalid, sizeof(invalid), collect, &units) == ASH264_INVALID);
    REQUIRE(units.size() == 3);

    const uint8_t too_big[] = {0, 0, 1, 0x65};
    REQUIRE(as_h264_feed(parser, too_big, sizeof(too_big), collect, &units) == ASH264_OK);
    std::vector<uint8_t> giant(64, 0x55);
    REQUIRE(as_h264_feed(parser, giant.data(), giant.size(), collect, &units) == ASH264_TOO_LARGE);
    REQUIRE(as_h264_feed(parser, too_big, sizeof(too_big), collect, &units) == ASH264_OK);
    REQUIRE(as_h264_finish(parser, collect, &units) == ASH264_OK);
    REQUIRE(units.size() == 4 && units.back().type == 5);

    // Deterministically split arbitrary Annex-B start codes across callbacks.
    std::vector<uint8_t> video = {0, 0, 0, 1, 0x67, 0x64, 0xab,
                                   0, 0, 1, 0x68, 0x34,
                                   0, 0, 0, 1, 0x65, 0x88, 0x12,
                                   0, 0, 1, 0x41, 0x99};
    std::mt19937 random(42);
    for (int run = 0; run < 64; ++run) {
        as_h264_reset(parser);
        std::vector<Unit> partitioned;
        for (size_t offset = 0; offset < video.size();) {
            const size_t count = std::min<size_t>(1 + (random() % 7), video.size() - offset);
            REQUIRE(as_h264_feed(parser, video.data() + offset, count,
                                 collect, &partitioned) == ASH264_OK);
            offset += count;
        }
        REQUIRE(as_h264_finish(parser, collect, &partitioned) == ASH264_OK);
        REQUIRE(partitioned.size() == 4);
        REQUIRE(partitioned[0].type == 7 && partitioned[1].type == 8);
        REQUIRE(partitioned[2].type == 5 && partitioned[3].type == 1);
    }

    // Multiple adjacent legal NAL units must not spuriously trigger the bound.
    as_h264_reset(parser);
    const uint8_t beginning[] = {0, 0, 1, 0x65};
    REQUIRE(as_h264_feed(parser, beginning, sizeof(beginning), collect, &units) == ASH264_OK);
    std::vector<uint8_t> combined(31, 0x71);
    combined.insert(combined.end(), {0, 0, 1, 0x67, 0x42});
    REQUIRE(as_h264_feed(parser, combined.data(), combined.size(), collect, &units) == ASH264_OK);
    REQUIRE(units.back().type == 5);
    as_h264_reset(parser);

    REQUIRE(as_h264_create(0) == nullptr);
    REQUIRE(as_h264_create((4u << 20) + 1) == nullptr);
    REQUIRE(as_h264_feed(parser, nullptr, 1, collect, &units) == ASH264_INVALID);
    as_h264_destroy(parser);
}
