#include "test_common.h"
#include "../Kernel/include/aerospatial_wire.h"
#include <cmath>
#include <cstring>
#include <limits>
int main() {
    unsigned char bytes[AS_HEAD_WIRE_BYTES]{};
    REQUIRE(as_head_wire_pack(12.25, 10, -20, 5, bytes, sizeof(bytes)));
    REQUIRE(!std::memcmp(bytes, "ASHD", 4));
    double t = 0, a = 0, b = 0, c = 0;
    REQUIRE(as_head_wire_unpack(bytes, sizeof(bytes), &t, &a, &b, &c));
    REQUIRE(std::abs(t - 12.25) < 1e-9 && a == 10 && b == -20 && c == 5);
    bytes[16] ^= 1;
    REQUIRE(!as_head_wire_unpack(bytes, sizeof(bytes), &t, &a, &b, &c));
    REQUIRE(!as_head_wire_pack(NAN, 1, 2, 3, bytes, sizeof(bytes)));
    REQUIRE(!as_head_wire_pack(1, 1, 2, 3, bytes, sizeof(bytes) - 1));
}
