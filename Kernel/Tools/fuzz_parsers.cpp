#include "aerospatial_h264.h"
#include "aerospatial_access_unit.h"
#include "aerospatial_wire.h"
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#ifdef AS_FUZZ_STANDALONE
#include <array>
#include <random>
#endif

namespace {
void on_nal(void *, const uint8_t *, size_t, uint8_t) {}
void on_unit(void *, const ASH264AccessUnit *) {}
}
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *bytes, size_t length) {
    if ((!bytes && length) || length > 8192) return 0;
    auto *p = as_h264_create(4096);
    auto *u = as_h264_access_create(4096, 8192);
    if (!p || !u) {
        as_h264_destroy(p);
        as_h264_access_destroy(u);
        return 0;
    }
    // Vary callback splitting and interleave ordinary and access-unit parsers.
    for (size_t offset = 0; offset < length;) {
        const size_t step = 1 + (static_cast<size_t>(bytes[offset]) % 29);
        const size_t chunk = std::min(step, length - offset);
        const auto h = as_h264_feed(p, bytes + offset, chunk, on_nal, nullptr);
        const auto a = as_h264_access_feed_dual(
            u, bytes + offset, chunk, on_nal, on_unit, nullptr);
        if (h != ASH264_OK || a != ASH264_OK) break;
        offset += chunk;
    }
    as_h264_finish(p, on_nal, nullptr);
    as_h264_access_finish_dual(u, on_nal, on_unit, nullptr);
    as_h264_destroy(p);
    as_h264_access_destroy(u);
    double uptime = 0, yaw = 0, pitch = 0, roll = 0;
    if (as_head_wire_unpack(bytes, length, &uptime, &yaw, &pitch, &roll)) {
        uint8_t packed[AS_HEAD_WIRE_BYTES]{};
        if (as_head_wire_pack(uptime, yaw, pitch, roll, packed, sizeof(packed))) {
            double a = 0, b = 0, c = 0, d = 0;
            if (!as_head_wire_unpack(packed, sizeof(packed), &a, &b, &c, &d))
                std::abort();
        }
    }
    // Include CRC edge cases, including empty and malformed payloads.
    (void)as_wire_crc32(bytes, length);
    return 0;
}
#ifdef AS_FUZZ_STANDALONE
int main() {
    std::mt19937 generator(20261113);
    std::uniform_int_distribution<int> length_dist(0, 4096);
    std::uniform_int_distribution<int> value_dist(0, 255);
    std::array<uint8_t, 4096> bytes{};
    for (int trial = 0; trial < 30000; ++trial) {
        const auto n = static_cast<size_t>(length_dist(generator));
        for (size_t i = 0; i < n; ++i)
            bytes[i] = static_cast<uint8_t>(value_dist(generator));
        if (n > 7 && trial % 4 == 0) {
            bytes[0] = bytes[1] = 0; bytes[2] = 1; bytes[3] = 0x67;
            bytes[n - 4] = bytes[n - 3] = 0; bytes[n - 2] = 1;
            bytes[n - 1] = 0x65;
        }
        LLVMFuzzerTestOneInput(bytes.data(), n);
    }
    return 0;
}
#endif
