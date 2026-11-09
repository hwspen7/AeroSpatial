#include "include/aerospatial_qos.h"
#include <cstdio>

int main() {
    auto *governor = as_qos_create();
    if (!governor || as_qos_configure(governor, {4, 20, 4, 700}) != ASQOS_ADMITTED)
        return 1;
    const uint64_t times[] = {0, 0, 50000000, 100000000, 99000000};
    const double costs[] = {3, 2, 2, 2, 1};
    const uint32_t pressure[] = {0, 0, 800, 0, 0};
    for (int index = 0; index < 5; ++index) {
        std::printf("%d\n", static_cast<int>(as_qos_admit(governor, 4,
                     times[index], costs[index], pressure[index])));
    }
    as_qos_destroy(governor);
    return 0;
}
