#include "bus_internal.hpp"
#include <algorithm>
#include <cstring>
#include <limits>
#include <new>

namespace {
constexpr uint32_t kKnownQuality = 0x3fu;
constexpr uint64_t kTopicLimitBytes = 128ull * 1024ull * 1024ull;

std::shared_ptr<BusTopic> find_topic(ASBus *bus, uint32_t id) {
    if (!bus) return {};
    std::lock_guard<std::mutex> lock(bus->mutex);
    auto found = bus->topics.find(id);
    return found == bus->topics.end() ? nullptr : found->second;
}
}  // namespace

extern "C" ASBus *as_bus_create(const ASBusConfig *config) {
    if (!config || !config->max_topics || config->max_topics > 64 ||
        !config->max_subscribers_per_topic || config->max_subscribers_per_topic > 128) return nullptr;
    try { return new ASBus(*config); } catch (...) { return nullptr; }
}

extern "C" void as_bus_destroy(ASBus *bus) {
    if (!bus) return;
    // Subscribers and fast publishers keep each topic alive after parent destruction.
    // This operation must not race with methods using the raw parent bus pointer.
    {
        std::lock_guard<std::mutex> lock(bus->mutex);
        for (auto &entry : bus->topics) {
            std::lock_guard<std::mutex> topic_lock(entry.second->mutex);
            entry.second->closed = true;
        }
    }
    delete bus;
}

extern "C" ASBusStatus as_bus_add_topic(ASBus *bus, ASBusTopicConfig config) {
    if (!bus || !config.stream_id || !config.capacity || config.capacity > 4096 ||
        !config.max_payload_bytes || config.max_payload_bytes > 8 * 1024 * 1024 ||
        (config.overflow != ASBUS_REJECT_NEWEST && config.overflow != ASBUS_OVERWRITE_OLDEST) ||
        uint64_t(config.capacity) * config.max_payload_bytes > kTopicLimitBytes) return ASBUS_INVALID;
    std::lock_guard<std::mutex> lock(bus->mutex);
    if (bus->topics.count(config.stream_id)) return ASBUS_INVALID;
    if (bus->topics.size() == bus->config.max_topics) return ASBUS_LIMIT_REACHED;
    try {
        bus->topics.emplace(config.stream_id,
                            std::make_shared<BusTopic>(config, bus->config.max_subscribers_per_topic, bus->budget));
        return ASBUS_OK;
    } catch (...) { return ASBUS_LIMIT_REACHED; }
}

extern "C" ASBusStatus as_bus_publish(ASBus *bus, ASBusHeader header,
                                       const void *payload, size_t payload_bytes) {
    auto topic = find_topic(bus, header.stream_id);
    return bus_publish_topic(topic, header, payload, payload_bytes);
}

ASBusStatus bus_publish_topic(const std::shared_ptr<BusTopic> &topic, ASBusHeader header,
                              const void *payload, size_t payload_bytes) {
    if (!topic) return ASBUS_INVALID;
    std::lock_guard<std::mutex> lock(topic->mutex);
    if (topic->closed) return ASBUS_CLOSED;
    if (header.sequence || !header.clock_domain ||
        !(header.quality_flags & ASBUS_QUALITY_VALID) ||
        (header.quality_flags & ~kKnownQuality) ||
        (!payload && payload_bytes) ||
        (topic->has_timestamp &&
         (header.clock_domain != topic->clock_domain || header.timestamp_ns < topic->last_timestamp))) {
        ++topic->stats.invalid;
        return topic->has_timestamp &&
            (header.clock_domain != topic->clock_domain || header.timestamp_ns < topic->last_timestamp)
            ? ASBUS_TIME_REGRESSION : ASBUS_INVALID;
    }
    if (payload_bytes > topic->config.max_payload_bytes) {
        ++topic->stats.rejected;
        return ASBUS_TOO_LARGE;
    }
    if (topic->config.overflow == ASBUS_REJECT_NEWEST) bus_trim_consumed(*topic);
    const bool full = topic->next - topic->oldest >= topic->config.capacity;
    if (full && topic->config.overflow == ASBUS_REJECT_NEWEST) {
        ++topic->stats.rejected;
        return ASBUS_BACKPRESSURE;
    }
    if (topic->next == std::numeric_limits<uint64_t>::max()) {
        ++topic->stats.rejected;
        return ASBUS_LIMIT_REACHED;
    }
    // Include payloads retained by external leases in the global accounting.
    // Reserve before allocating and roll back on allocation failure.
    if (!topic->budget->reserve(payload_bytes)) {
        ++topic->stats.rejected;
        ++topic->stats.budget_rejected;
        return ASBUS_MEMORY_BUDGET;
    }
    struct Reservation {
        BusBudget &budget;
        uint64_t bytes;
        ~Reservation() { budget.release(bytes); }
    } reservation{*topic->budget, static_cast<uint64_t>(payload_bytes)};
    try {
        auto event = std::make_shared<BusEvent>();
        event->budget = topic->budget;
        event->reserved_bytes = 0;
        header.sequence = topic->next;
        event->header = header;
        if (payload_bytes) {
            const auto *first = static_cast<const uint8_t *>(payload);
            event->payload.assign(first, first + payload_bytes);
        }
        if (full) {
            auto &evicted = topic->slots[bus_slot(*topic, topic->oldest)];
            topic->stats.retained_bytes -= evicted->payload.size();
            ++topic->oldest;
            ++topic->stats.overwritten;
        }
        // Transfer accounting only after every potentially throwing allocation.
        event->reserved_bytes = payload_bytes;
        reservation.bytes = 0;
        topic->slots[bus_slot(*topic, topic->next)] = std::move(event);
    } catch (...) {
        // The event's destructor releases the reservation once constructed.
        // Allocation of BusEvent itself is handled by the guard below.
        ++topic->stats.rejected;
        return ASBUS_LIMIT_REACHED;
    }
    ++topic->next;
    ++topic->stats.published;
    topic->stats.retained_bytes += payload_bytes;
    topic->stats.high_water_bytes = std::max(topic->stats.high_water_bytes,
                                             topic->stats.retained_bytes);
    topic->stats.retained_events = static_cast<uint32_t>(topic->next - topic->oldest);
    topic->stats.next_sequence = topic->next;
    topic->last_timestamp = header.timestamp_ns;
    topic->clock_domain = header.clock_domain;
    topic->has_timestamp = true;
    return ASBUS_OK;
}

extern "C" ASBusStatus as_bus_set_payload_budget(ASBus *bus, uint64_t bytes) {
    if (!bus || !bytes || bytes > (1ull << 34)) return ASBUS_INVALID;
    std::lock_guard<std::mutex> lock(bus->mutex);
    // Configure before adding topics; no producer can race with configuration.
    if (!bus->topics.empty()) return ASBUS_BUSY;
    bus->budget->limit.store(bytes, std::memory_order_release);
    return ASBUS_OK;
}

extern "C" ASBusStatus as_bus_memory_stats(ASBus *bus, ASBusMemoryStats *stats) {
    if (!bus || !stats) return ASBUS_INVALID;
    std::lock_guard<std::mutex> lock(bus->mutex);
    stats->limit_bytes = bus->budget->limit.load(std::memory_order_acquire);
    stats->live_bytes = bus->budget->live.load(std::memory_order_acquire);
    stats->high_water_bytes = bus->budget->peak.load(std::memory_order_acquire);
    return ASBUS_OK;
}

extern "C" ASBusPublisher *as_bus_open_publisher(ASBus *bus, uint32_t stream_id) {
    auto topic = find_topic(bus, stream_id);
    if (!topic) return nullptr;
    std::lock_guard<std::mutex> lock(topic->mutex);
    if (topic->closed) return nullptr;
    return new (std::nothrow) ASBusPublisher{std::move(topic)};
}

extern "C" ASBusStatus as_bus_publish_fast(ASBusPublisher *publisher, ASBusHeader header,
                                             const void *payload, size_t payload_bytes) {
    if (!publisher || header.stream_id != publisher->topic->config.stream_id) return ASBUS_INVALID;
    return bus_publish_topic(publisher->topic, header, payload, payload_bytes);
}

extern "C" void as_bus_close_publisher(ASBusPublisher *publisher) { delete publisher; }

extern "C" ASBusStatus as_bus_stats(ASBus *bus, uint32_t stream_id,
                                    ASBusTopicStats *stats) {
    if (!stats) return ASBUS_INVALID;
    auto topic = find_topic(bus, stream_id);
    if (!topic) return ASBUS_INVALID;
    std::lock_guard<std::mutex> lock(topic->mutex);
    *stats = topic->stats;
    return ASBUS_OK;
}
