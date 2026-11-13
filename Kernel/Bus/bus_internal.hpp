#ifndef AEROSPATIAL_BUS_INTERNAL_H
#define AEROSPATIAL_BUS_INTERNAL_H

#include "aerospatial_bus.h"
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

struct BusBudget {
    explicit BusBudget(uint64_t initial_limit) : limit(initial_limit) {}
    std::atomic<uint64_t> limit;
    std::atomic<uint64_t> live{0};
    std::atomic<uint64_t> peak{0};

    bool reserve(uint64_t bytes) noexcept {
        if (!bytes) return true;
        uint64_t old = live.load(std::memory_order_relaxed);
        while (true) {
            const uint64_t cap = limit.load(std::memory_order_relaxed);
            if (old > cap || bytes > cap - old) return false;
            if (live.compare_exchange_weak(old, old + bytes, std::memory_order_acq_rel)) {
                uint64_t current = peak.load(std::memory_order_relaxed);
                while (current < old + bytes &&
                       !peak.compare_exchange_weak(current, old + bytes, std::memory_order_relaxed)) {}
                return true;
            }
        }
    }
    void release(uint64_t bytes) noexcept {
        if (bytes) live.fetch_sub(bytes, std::memory_order_acq_rel);
    }
};

struct BusEvent {
    ASBusHeader header{};
    std::vector<uint8_t> payload;
    std::shared_ptr<BusBudget> budget;
    uint64_t reserved_bytes = 0;
    ~BusEvent() { if (budget) budget->release(reserved_bytes); }
};

struct BusCursor {
    uint64_t next = 1;
    bool leased = false;
};

struct BusTopic {
    explicit BusTopic(ASBusTopicConfig options, uint32_t subscriber_limit,
                      std::shared_ptr<BusBudget> budget_ref)
        : config(options), limit(subscriber_limit), budget(std::move(budget_ref)),
          slots(options.capacity) {}
    const ASBusTopicConfig config;
    const uint32_t limit;
    std::shared_ptr<BusBudget> budget;
    bool closed = false;
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
    explicit ASBus(ASBusConfig cfg)
        : config(cfg), budget(std::make_shared<BusBudget>(256ull * 1024ull * 1024ull)) {}
    ASBusConfig config;
    std::shared_ptr<BusBudget> budget;
    std::mutex mutex;
    std::unordered_map<uint32_t, std::shared_ptr<BusTopic>> topics;
};

struct ASBusPublisher {
    std::shared_ptr<BusTopic> topic;
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

/* Called with a shared topic handle; excludes lookups from the hot path. */
ASBusStatus bus_publish_topic(const std::shared_ptr<BusTopic> &topic, ASBusHeader header,
                              const void *payload, size_t payload_bytes);

/* Called under topic mutex. Reclaim fully read messages in reject-newest mode. */
void bus_trim_consumed(BusTopic &topic);

/* Returns the next event without changing the cursor. Called under mutex. */
std::shared_ptr<const BusEvent> bus_next(BusTopic &topic, BusCursor &cursor,
                                         uint64_t &missed);

#endif
