#include "include/aerospatial_wire.h"
#include <cstdio>

int main() {
    unsigned char record[AS_HEAD_WIRE_BYTES]{};
    if (!as_head_wire_pack(12.25, 10, -20, 5, record, sizeof(record))) return 2;
    for (unsigned char byte : record) std::printf("%02x", unsigned(byte));
    std::puts("");
}
