#ifndef AEROSPATIAL_ACCESS_UNIT_H
#define AEROSPATIAL_ACCESS_UNIT_H

#include <stddef.h>
#include <stdint.h>
#include "aerospatial_h264.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ASH264AccessAssembler ASH264AccessAssembler;

typedef struct {
    const uint8_t *avcc_bytes;
    size_t avcc_size;
    const uint8_t *sps_bytes;
    size_t sps_size;
    const uint8_t *pps_bytes;
    size_t pps_size;
    uint64_t ordinal;
    uint8_t keyframe;
} ASH264AccessUnit;

/// All pointers are borrowed until the callback returns. Copy for asynchronous use.
/// AVCC data consists of big-endian uint32 NAL lengths followed by NAL bytes.
/// No image decoding, PTS reconstruction, or flight action is performed here.
typedef void (*ASH264AccessCallback)(void *context, const ASH264AccessUnit *unit);

/// Serial-use assembler. max_nal is 1..4 MiB; max_access is 1..8 MiB.
/// Requires SPS, PPS and an IDR to resynchronize following a reset or gap.
ASH264AccessAssembler *as_h264_access_create(size_t max_nal, size_t max_access);
void as_h264_access_destroy(ASH264AccessAssembler *assembler);
void as_h264_access_reset(ASH264AccessAssembler *assembler);
ASH264Status as_h264_access_feed(ASH264AccessAssembler *assembler, const uint8_t *bytes,
                                size_t length, ASH264AccessCallback callback, void *context);
/// Call only on a confirmed EOS, never on packet loss or pause.
ASH264Status as_h264_access_finish(ASH264AccessAssembler *assembler,
                                  ASH264AccessCallback callback, void *context);

#ifdef __cplusplus
}
#endif
#endif
