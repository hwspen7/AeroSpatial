#ifndef AEROSPATIAL_BUS_INTERNAL_H
#define AEROSPATIAL_BUS_INTERNAL_H

#include "aerospatial_bus.h"
#include <cstdint>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

struct BusEvent {
    ASBusHeader header{};
    std::vector<uint8_t> payload;
};

struct BusCursor {
    uint64_t next = 1;
    bool leased = false;
};

struct BusTopic {
    explicit BusTopic(ASBusTopicConfig options, uint32_t subscriber_limit)
        : config(options), limit(subscriber_limit), slots(options.capacity) {}
    const ASBusTopicConfig config;
    const uint32_t limit;
    std::mutex mutex;
    std::vector<std::shared_ptr<const BusEvent>> slots;
    std::vector<std::weak_ptr<BusCursor>> cursors;
    ASBusTopicStats stats{};
    uint64_t next = 1;
    uint64_t oldest = 1;
    uint64_t last_timestamp = 0;
    uint32_t clock_domain = 0;
    bool has_timestamp = false;
};

struct ASBus {
    explicit ASBus(ASBusConfig cfg) : config(cfg) {}
    ASBusConfig config;
    std::mutex mutex;
    std::unordered_map<uint32_t, std::shared_ptr<BusTopic>> topics;
};

struct ASBusSubscription {
    std::shared_ptr<BusTopic> topic;
    std::shared_ptr<BusCursor> cursor;
};

struct ASBusLease {
    std::shared_ptr<const BusEvent> event;
    std::shared_ptr<BusTopic> topic;
    std::shared_ptr<BusCursor> cursor;
};

inline size_t bus_slot(const BusTopic &topic, uint64_t seq) {
    return static_cast<size_t>((seq - 1) % topic.config.capacity);
}

/* Called under topic mutex. Reclaim fully read messages in reject-newest mode. */
void bus_trim_consumed(BusTopic &topic);

/* Returns the next event without changing the cursor. Called under mutex. */
std::shared_ptr<const BusEvent> bus_next(BusTopic &topic, BusCursor &cursor,
                                         uint64_t &missed);

#endif
