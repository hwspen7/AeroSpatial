#include "include/aerospatial_wire.h"
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>

namespace {
void put64(uint8_t *out, uint64_t value) {
    for (unsigned i = 0; i < 8; ++i) out[i] = static_cast<uint8_t>(value >> (8 * i));
}
uint64_t get64(const uint8_t *in) {
    uint64_t value = 0;
    for (unsigned i = 0; i < 8; ++i) value |= uint64_t(in[i]) << (8 * i);
    return value;
}
uint32_t crc32(const uint8_t *data, size_t count) {
    uint32_t result = 0xffffffffu;
    for (size_t i = 0; i < count; ++i) {
        result ^= data[i];
        for (int j = 0; j < 8; ++j) result = (result >> 1) ^ (0xedb88320u & -(result & 1u));
    }
    return ~result;
}
void put_double(uint8_t *out, double value) {
    uint64_t bits = 0;
    std::memcpy(&bits, &value, 8);
    put64(out, bits);
}
double get_double(const uint8_t *in) {
    const uint64_t bits = get64(in);
    double value = 0;
    std::memcpy(&value, &bits, 8);
    return value;
}
}
extern "C" uint32_t as_wire_crc32(const void *bytes, size_t length) {
    if (!bytes && length) return 0;
    return crc32(static_cast<const uint8_t *>(bytes), length);
}
extern "C" int as_head_wire_pack(double uptime, double yaw, double pitch, double roll,
                                   void *out, size_t capacity) {
    if (!out || capacity < AS_HEAD_WIRE_BYTES || !std::isfinite(uptime) || uptime < 0 ||
        uptime >= double(std::numeric_limits<uint64_t>::max()) / 1e9 ||
        !std::isfinite(yaw) || !std::isfinite(pitch) || !std::isfinite(roll)) return 0;
    auto *ptr = static_cast<uint8_t *>(out);
    ptr[0] = 'A'; ptr[1] = 'S'; ptr[2] = 'H'; ptr[3] = 'D';
    ptr[4] = 1; ptr[5] = 0; ptr[6] = 0; ptr[7] = 0;
    put64(ptr + 8, static_cast<uint64_t>(uptime * 1e9));
    put_double(ptr + 16, yaw); put_double(ptr + 24, pitch); put_double(ptr + 32, roll);
    const uint32_t checksum = crc32(ptr, 40);
    for (unsigned i = 0; i < 4; ++i) ptr[40 + i] = static_cast<uint8_t>(checksum >> (8 * i));
    return 1;
}
extern "C" int as_head_wire_unpack(const void *data, size_t size, double *uptime,
                                     double *yaw, double *pitch, double *roll) {
    if (!data || size != AS_HEAD_WIRE_BYTES || !uptime || !yaw || !pitch || !roll) return 0;
    auto *ptr = static_cast<const uint8_t *>(data);
    if (std::memcmp(ptr, "ASHD", 4) || ptr[4] != 1 || ptr[5] || ptr[6] || ptr[7]) return 0;
    const uint32_t expected = uint32_t(ptr[40]) | (uint32_t(ptr[41]) << 8) |
        (uint32_t(ptr[42]) << 16) | (uint32_t(ptr[43]) << 24);
    if (crc32(ptr, 40) != expected) return 0;
    const double timestamp = double(get64(ptr + 8)) / 1e9;
    const double a = get_double(ptr + 16), b = get_double(ptr + 24), c = get_double(ptr + 32);
    if (!std::isfinite(timestamp) || !std::isfinite(a) || !std::isfinite(b) || !std::isfinite(c)) return 0;
    *uptime = timestamp; *yaw = a; *pitch = b; *roll = c;
    return 1;
}
