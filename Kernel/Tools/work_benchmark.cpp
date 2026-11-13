#include "include/aerospatial_work_queue.h"
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

int main(int argc, char **argv) {
    const uint64_t count = argc >= 2 ? std::strtoull(argv[1], nullptr, 10) : 100000;
    const uint64_t bytes = argc >= 3 ? std::strtoull(argv[2], nullptr, 10) : 1024;
    if (count < 1 || count > 10000000 || bytes < 1 || bytes > 1u << 20) return 2;
    const auto size = static_cast<size_t>(bytes);
    const std::vector<uint8_t> input(size, 42);
    std::vector<uint8_t> output(size);
    auto *queue = as_work_queue_create(32, size * 32, size);
    if (!queue) return 3;
    const auto start = std::chrono::steady_clock::now();
    ASWorkHeader read{};
    size_t length = 0;
    for (uint64_t id = 0; id < count; ++id) {
        ASWorkHeader header{id, id + 1, id + 1000000, 2, ASWQ_OPTIONAL};
        if (as_work_queue_push(queue, header, input.data(), size, id + 1) != ASWQ_OK ||
            as_work_queue_pop(queue, id + 2, &read, output.data(), output.size(), &length) != ASWQ_OK ||
            read.trace_id != id || length != size) {
            as_work_queue_destroy(queue);
            return 4;
        }
    }
    const auto stop = std::chrono::steady_clock::now();
    ASWorkStats stats{};
    as_work_queue_stats(queue, &stats);
    as_work_queue_destroy(queue);
    const double seconds = std::chrono::duration<double>(stop - start).count();
    std::cout << "native_queue_iterations=" << count << " payload_bytes=" << bytes
              << " seconds=" << seconds << " events_per_second=" << count / seconds
              << " high_water_bytes=" << stats.high_water_bytes
              << " rejected=" << stats.rejected << " expired=" << stats.expired << "\n";
    return 0;
}
