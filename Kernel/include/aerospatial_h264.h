#ifndef AEROSPATIAL_H264_H
#define AEROSPATIAL_H264_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ASH264Parser ASH264Parser;
typedef enum {
    ASH264_OK = 0,
    ASH264_INVALID = 1,
    ASH264_TOO_LARGE = 2
} ASH264Status;

/// A parsed NAL unit (not a complete video frame). The data pointer is valid
/// only for the duration of the callback. No decoding or image allocation occurs.
typedef void (*ASH264NalCallback)(void *context, const uint8_t *bytes, size_t size,
                                  uint8_t nal_type);

/// Maximum single NAL body size is 1..4 MiB; input chunks are bounded by it too.
/// The parser is not thread-safe. Use one instance per serial video source.
ASH264Parser *as_h264_create(size_t maximum_nal_bytes);
void as_h264_destroy(ASH264Parser *parser);
void as_h264_reset(ASH264Parser *parser);
ASH264Status as_h264_feed(ASH264Parser *parser, const uint8_t *bytes, size_t size,
                          ASH264NalCallback callback, void *context);
/// Emit the final NAL after an explicit stream end. Not safe for partial chunks.
ASH264Status as_h264_finish(ASH264Parser *parser, ASH264NalCallback callback, void *context);

#ifdef __cplusplus
}
#endif
#endif
