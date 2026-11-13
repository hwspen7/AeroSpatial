#include "include/aerospatial_h264.h"
#include <algorithm>
#include <new>
#include <vector>

struct ASH264Parser {
    explicit ASH264Parser(size_t limit) : maximum(limit) {}
    size_t maximum;
    std::vector<uint8_t> pending;
    bool synchronized = false;
    size_t marker_size = 0;
};

namespace {
struct Marker { size_t position; size_t size; };

Marker find_marker(const std::vector<uint8_t> &data, size_t begin) {
    for (size_t i = begin; i + 2 < data.size(); ++i) {
        if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
            // An extra leading zero is Annex-B's four-byte start code.
            if (i > 0 && data[i - 1] == 0 && i - 1 >= begin)
                return {i - 1, 4};
            return {i, 3};
        }
    }
    return {data.size(), 0};
}

ASH264Status emit(const std::vector<uint8_t> &data, size_t start, size_t end,
                   size_t maximum, ASH264NalCallback cb, void *context) {
    while (end > start && data[end - 1] == 0) --end; // Annex-B trailing_zero_8bits
    if (start >= end || end - start > maximum) return ASH264_INVALID;
    const uint8_t type = data[start] & 0x1f;
    if ((data[start] & 0x80) || !type || type >= 24) return ASH264_INVALID;
    cb(context, data.data() + start, end - start, type);
    return ASH264_OK;
}
} // namespace

extern "C" ASH264Parser *as_h264_create(size_t maximum_nal_bytes) {
    if (!maximum_nal_bytes || maximum_nal_bytes > (4u << 20)) return nullptr;
    try { return new ASH264Parser(maximum_nal_bytes); } catch (...) { return nullptr; }
}

extern "C" void as_h264_destroy(ASH264Parser *parser) { delete parser; }
extern "C" void as_h264_reset(ASH264Parser *parser) {
    if (!parser) return;
    parser->pending.clear();
    parser->synchronized = false;
    parser->marker_size = 0;
}

namespace {
ASH264Status process_buffer(ASH264Parser *parser, size_t old_count,
                          ASH264NalCallback callback, void *context) {
    size_t search_start = old_count > 4 ? old_count - 4 : 0;
    for (;;) {
        if (!parser->synchronized) {
            const auto first = find_marker(parser->pending, 0);
            if (!first.size) {
                const size_t tail = std::min<size_t>(3, parser->pending.size());
                if (parser->pending.size() > tail)
                    parser->pending.erase(parser->pending.begin(), parser->pending.end() - tail);
                return ASH264_OK;
            }
            parser->pending.erase(parser->pending.begin(),
                                  parser->pending.begin() + first.position);
            parser->synchronized = true;
            parser->marker_size = first.size;
            search_start = parser->marker_size;
        }
        const auto next = find_marker(parser->pending,
            std::max(parser->marker_size, search_start));
        if (!next.size) {
            if (parser->pending.size() > parser->maximum + parser->marker_size) {
                as_h264_reset(parser);
                return ASH264_TOO_LARGE;
            }
            return ASH264_OK;
        }
        const auto status = emit(parser->pending, parser->marker_size, next.position,
                                 parser->maximum, callback, context);
        if (status != ASH264_OK) { as_h264_reset(parser); return status; }
        parser->pending.erase(parser->pending.begin(),
                              parser->pending.begin() + next.position);
        parser->marker_size = next.size;
        search_start = parser->marker_size;
    }
}
} // namespace

extern "C" ASH264Status as_h264_feed(ASH264Parser *parser, const uint8_t *bytes,
                                      size_t size, ASH264NalCallback callback, void *context) {
    if (!parser || !callback || (!bytes && size) || size > parser->maximum)
        return ASH264_INVALID;
    if (size == 0) return ASH264_OK;
    // Slice large SDK callbacks so one valid NAL followed by another does not
    // spuriously exceed the accumulation limit before the first is dispatched.
    const size_t increment = std::min<size_t>(16384, parser->maximum);
    for (size_t offset = 0; offset < size;) {
        const size_t count = std::min(increment, size - offset);
        const size_t old_count = parser->pending.size();
        try {
            parser->pending.insert(parser->pending.end(), bytes + offset,
                                   bytes + offset + count);
        } catch (...) {
            as_h264_reset(parser);
            return ASH264_TOO_LARGE;
        }
        const auto status = process_buffer(parser, old_count, callback, context);
        if (status != ASH264_OK) return status;
        offset += count;
    }
    return ASH264_OK;
}

extern "C" ASH264Status as_h264_finish(ASH264Parser *parser,
                                        ASH264NalCallback callback, void *context) {
    if (!parser || !callback) return ASH264_INVALID;
    ASH264Status result = ASH264_OK;
    if (parser->synchronized) {
        result = emit(parser->pending, parser->marker_size, parser->pending.size(),
                      parser->maximum, callback, context);
    }
    as_h264_reset(parser);
    return result;
}
