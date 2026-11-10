#include "include/aerospatial_access_unit.h"
#include <algorithm>
#include <limits>
#include <new>
#include <vector>

struct ASH264AccessAssembler {
    ASH264Parser *parser = nullptr;
    size_t maximum = 0;
    std::vector<uint8_t> sps, pps, frame;
    bool has_vcl = false;
    bool keyframe = false;
    bool need_idr = true;
    uint64_t ordinal = 0;
    ASH264Status error = ASH264_OK;
    ASH264AccessCallback callback = nullptr;
    ASH264NalCallback nal_callback = nullptr;
    void *context = nullptr;
};

namespace {
// Only the first unsigned Exp-Golomb code (first_mb_in_slice) is required.
// Skip emulation-prevention bytes. An invalid/truncated slice is rejected.
bool first_mb(const uint8_t *nal, size_t count, uint32_t *first) {
    if (!nal || count < 2 || !first) return false;
    uint32_t zeros = 0, value = 1;
    int previous_zeros = 0;
    size_t byte = 1;
    unsigned bit = 8;
    const auto next = [&]() mutable -> int {
        for (;;) {
            if (bit < 8) return (nal[byte - 1] >> (7 - bit++)) & 1;
            if (byte >= count) return -1;
            if (previous_zeros == 2 && nal[byte] == 3) {
                ++byte;
                previous_zeros = 0;
                if (byte >= count) return -1;
            }
            const uint8_t current = nal[byte++];
            previous_zeros = current == 0 ? std::min(previous_zeros + 1, 2) : 0;
            bit = 0;
        }
    };
    auto reader = next;
    for (;;) {
        const int b = reader();
        if (b < 0 || zeros >= 31) return false;
        if (b == 1) break;
        ++zeros;
    }
    for (uint32_t i = 0; i < zeros; ++i) {
        const int b = reader();
        if (b < 0) return false;
        value = (value << 1) | static_cast<uint32_t>(b);
    }
    *first = value - 1;
    return true;
}

void flush(ASH264AccessAssembler *a) {
    if (!a->has_vcl || a->frame.empty() || !a->callback) return;
    ASH264AccessUnit unit{};
    unit.avcc_bytes = a->frame.data();
    unit.avcc_size = a->frame.size();
    unit.sps_bytes = a->sps.data();
    unit.sps_size = a->sps.size();
    unit.pps_bytes = a->pps.data();
    unit.pps_size = a->pps.size();
    unit.ordinal = ++a->ordinal;
    unit.keyframe = a->keyframe ? 1 : 0;
    a->callback(a->context, &unit);
    a->frame.clear();
    a->has_vcl = false;
    a->keyframe = false;
}

void receive_nal(void *opaque, const uint8_t *nal, size_t size, uint8_t type) {
    auto *a = static_cast<ASH264AccessAssembler *>(opaque);
    if (a->error != ASH264_OK) return;
    if (a->nal_callback) a->nal_callback(a->context, nal, size, type);
    if (type == 9) { // Access-unit delimiter.
        flush(a);
        return;
    }
    if (type == 7 || type == 8) {
        // A parameter-set change cannot be attached to a frame in progress.
        flush(a);
        if (type == 7) a->sps.assign(nal, nal + size);
        else a->pps.assign(nal, nal + size);
        a->need_idr = true;
        return;
    }
    if (type == 6) { // SEI is metadata for the following picture.
        flush(a);
        return;
    }
    if (type != 1 && type != 5) {
        if (type >= 2 && type <= 4) a->error = ASH264_INVALID; // unsupported data partitioning
        return;
    }
    uint32_t first = 0;
    if (!first_mb(nal, size, &first)) {
        a->error = ASH264_INVALID;
        return;
    }
    if (a->has_vcl && first == 0) flush(a);
    if (!a->has_vcl) {
        if (first != 0 || a->sps.empty() || a->pps.empty() ||
            (a->need_idr && type != 5)) return;
        a->need_idr = false;
        a->keyframe = type == 5;
        a->has_vcl = true;
    } else if (type != 1 && type != 5) {
        a->error = ASH264_INVALID;
        return;
    }
    if (size > a->maximum || a->frame.size() > a->maximum - size - 4) {
        a->error = ASH264_TOO_LARGE;
        return;
    }
    const auto n = static_cast<uint32_t>(size);
    for (int shift : {24, 16, 8, 0})
        a->frame.push_back(static_cast<uint8_t>(n >> shift));
    a->frame.insert(a->frame.end(), nal, nal + size);
}

void reset(ASH264AccessAssembler *a) {
    as_h264_reset(a->parser);
    a->frame.clear();
    a->sps.clear();
    a->pps.clear();
    a->has_vcl = false;
    a->keyframe = false;
    a->need_idr = true;
    a->error = ASH264_OK;
}
}

extern "C" ASH264AccessAssembler *as_h264_access_create(size_t max_nal, size_t max_access) {
    if (!max_nal || max_nal > (4u << 20) || max_access < 8 ||
        max_access > (8u << 20) || max_access < max_nal + 4) return nullptr;
    auto *result = new (std::nothrow) ASH264AccessAssembler;
    if (!result) return nullptr;
    result->parser = as_h264_create(max_nal);
    if (!result->parser) { delete result; return nullptr; }
    result->maximum = max_access;
    return result;
}
extern "C" void as_h264_access_destroy(ASH264AccessAssembler *a) {
    if (!a) return;
    as_h264_destroy(a->parser);
    delete a;
}
extern "C" void as_h264_access_reset(ASH264AccessAssembler *a) {
    if (a) reset(a);
}
extern "C" ASH264Status as_h264_access_feed(ASH264AccessAssembler *a, const uint8_t *data,
                                              size_t n, ASH264AccessCallback cb, void *ctx) {
    if (!a || !cb || (!data && n)) return ASH264_INVALID;
    a->callback = cb;
    a->nal_callback = nullptr;
    a->context = ctx;
    a->error = ASH264_OK;
    ASH264Status status = ASH264_INVALID;
    try { status = as_h264_feed(a->parser, data, n, receive_nal, a); }
    catch (...) { status = ASH264_TOO_LARGE; }
    if (status == ASH264_OK) status = a->error;
    if (status != ASH264_OK) reset(a);
    return status;
}
extern "C" ASH264Status as_h264_access_feed_dual(ASH264AccessAssembler *a,
        const uint8_t *data, size_t n, ASH264NalCallback nal_cb,
        ASH264AccessCallback access_cb, void *ctx) {
    if (!a || (!nal_cb && !access_cb) || (!data && n)) return ASH264_INVALID;
    a->callback = access_cb;
    a->nal_callback = nal_cb;
    a->context = ctx;
    a->error = ASH264_OK;
    ASH264Status status = ASH264_INVALID;
    try { status = as_h264_feed(a->parser, data, n, receive_nal, a); }
    catch (...) { status = ASH264_TOO_LARGE; }
    if (status == ASH264_OK) status = a->error;
    if (status != ASH264_OK) reset(a);
    a->nal_callback = nullptr;
    return status;
}
extern "C" ASH264Status as_h264_access_finish_dual(ASH264AccessAssembler *a,
        ASH264NalCallback nal_cb, ASH264AccessCallback access_cb, void *ctx) {
    if (!a || (!nal_cb && !access_cb)) return ASH264_INVALID;
    a->callback = access_cb;
    a->nal_callback = nal_cb;
    a->context = ctx;
    a->error = ASH264_OK;
    ASH264Status status = ASH264_INVALID;
    try { status = as_h264_finish(a->parser, receive_nal, a); }
    catch (...) { status = ASH264_TOO_LARGE; }
    if (status == ASH264_OK) status = a->error;
    if (status == ASH264_OK) flush(a);
    reset(a);
    a->nal_callback = nullptr;
    return status;
}
extern "C" ASH264Status as_h264_access_finish(ASH264AccessAssembler *a,
                                                ASH264AccessCallback cb, void *ctx) {
    if (!cb) return ASH264_INVALID;
    return as_h264_access_finish_dual(a, nullptr, cb, ctx);
}
