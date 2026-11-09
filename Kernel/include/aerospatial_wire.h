#ifndef AEROSPATIAL_WIRE_H
#define AEROSPATIAL_WIRE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Fixed-size, little-endian, CRC-protected motion record. No heap allocation. */
enum { AS_HEAD_WIRE_BYTES = 44, AS_HEAD_WIRE_KIND = 1 };
uint32_t as_wire_crc32(const void *bytes, size_t length);
int as_head_wire_pack(double uptime_seconds, double yaw, double pitch, double roll,
                      void *out, size_t capacity);
int as_head_wire_unpack(const void *data, size_t size, double *uptime_seconds,
                        double *yaw, double *pitch, double *roll);
#ifdef __cplusplus
}
#endif
#endif
