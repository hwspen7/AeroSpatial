#include "aerospatial_native.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <vector>

int main(int argc, char **argv) {
    const size_t count = argc > 1 ? static_cast<size_t>(std::strtoull(argv[1], nullptr, 10)) : 500000;
    if (count < 1 || count > 10000000) return 2;
    std::vector<ASGeodetic3> positions(count);
    std::vector<ASVector3> output(count);
    for (size_t i = 0; i < count; ++i) {
        positions[i] = {39.0 + (i % 3000) * 0.0001, -83.0 + (i % 4000) * 0.0001, 200};
    }
    volatile double checksum = 0;
    auto start = std::chrono::steady_clock::now();
    if (as_wgs84_ecef_batch(positions.data(), count, output.data()) != AS_OK) return 3;
    auto end = std::chrono::steady_clock::now();
    for (size_t i = 0; i < count; ++i) checksum += output[i].x * 1e-12;
    double seconds = std::chrono::duration<double>(end - start).count();
    std::cout << "{\"operation\":\"wgs84_ecef_batch\",\"samples\":" << count
              << ",\"seconds\":" << seconds << ",\"samples_per_second\":"
              << count / seconds << ",\"checksum\":" << checksum << "}\n";
    return 0;
}
