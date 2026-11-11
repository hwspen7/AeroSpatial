#include "test_common.h"
#include "../Kernel/include/aerospatial_access_unit.h"
#include <algorithm>
#include <fstream>
#include <iterator>
#include <random>
#include <string>
#include <vector>

struct Frame { bool key; size_t bytes; size_t sps; size_t pps; };
static void collect(void *opaque, const ASH264AccessUnit *item) {
    static_cast<std::vector<Frame> *>(opaque)->push_back(
        {item->keyframe != 0, item->avcc_size, item->sps_size, item->pps_size});
}

int main() {
    std::ifstream input(std::string(AEROSPATIAL_FIXTURE_DIR) + "/h264-six-frames.264",
                        std::ios::binary);
    REQUIRE(input.good());
    const std::vector<uint8_t> stream(std::istreambuf_iterator<char>{input}, {});
    REQUIRE(stream.size() > 200 && stream.size() < 65536);
    auto *assembler = as_h264_access_create(4096, 16384);
    REQUIRE(assembler);
    std::vector<Frame> reference;
    REQUIRE(as_h264_access_feed(assembler, stream.data(), stream.size(), collect, &reference) == ASH264_OK);
    REQUIRE(as_h264_access_finish(assembler, collect, &reference) == ASH264_OK);
    REQUIRE(reference.size() == 6);
    REQUIRE(reference[0].key && reference[3].key);
    for (auto &frame : reference) {
        REQUIRE(frame.bytes > 0 && frame.sps > 0 && frame.pps > 0);
    }
    std::mt19937 generator(503);
    for (int repeat = 0; repeat < 100; ++repeat) {
        as_h264_access_reset(assembler);
        std::vector<Frame> actual;
        for (size_t offset = 0; offset < stream.size();) {
            const auto block = std::min<size_t>(1 + generator() % 41, stream.size() - offset);
            REQUIRE(as_h264_access_feed(assembler, stream.data() + offset,
                                        block, collect, &actual) == ASH264_OK);
            offset += block;
        }
        REQUIRE(as_h264_access_finish(assembler, collect, &actual) == ASH264_OK);
        REQUIRE(actual.size() == reference.size());
        for (size_t i = 0; i < actual.size(); ++i) {
            REQUIRE(actual[i].key == reference[i].key);
            REQUIRE(actual[i].bytes == reference[i].bytes);
            REQUIRE(actual[i].sps == reference[i].sps);
        }
    }
    // Discarding half a stream is a discontinuity; stale pictures are forbidden.
    as_h264_access_reset(assembler);
    std::vector<Frame> after_gap;
    REQUIRE(as_h264_access_feed(assembler, stream.data() + stream.size()/2,
                                stream.size() - stream.size()/2,
                                collect, &after_gap) == ASH264_OK);
    REQUIRE(as_h264_access_finish(assembler, collect, &after_gap) == ASH264_OK);
    REQUIRE(after_gap.size() <= 3);
    REQUIRE(after_gap.empty() || after_gap.front().key);
    as_h264_access_destroy(assembler);
}
