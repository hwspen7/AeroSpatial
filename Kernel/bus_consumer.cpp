#include "bus_internal.hpp"
#include <cstring>
#include <memory>
#include <new>

void bus_trim_consumed(BusTopic &topic) {
    uint64_t minimum = topic.next;
    bool has_subscriber = false;
    auto out = topic.cursors.begin();
    for (auto iter = topic.cursors.begin(); iter != topic.cursors.end(); ++iter) {
        if (auto cursor = iter->lock()) {
            has_subscriber = true;
            minimum = std::min(minimum, cursor->next);
            *out++ = *iter;
        }
    }
    topic.cursors.erase(out, topic.cursors.end());
    topic.stats.active_subscribers = static_cast<uint32_t>(topic.cursors.size());
    if (!has_subscriber) return;  // Retain until a reader exists.
    while (topic.oldest < minimum && topic.oldest < topic.next) {
        auto &slot = topic.slots[bus_slot(topic, topic.oldest)];
        if (slot) {
            topic.stats.retained_bytes -= slot->payload.size();
            slot.reset();
        }
        ++topic.oldest;
    }
    topic.stats.retained_events = static_cast<uint32_t>(topic.next - topic.oldest);
}

std::shared_ptr<const BusEvent> bus_next(BusTopic &topic, BusCursor &cursor,
                                         uint64_t &missed) {
    missed = cursor.next < topic.oldest ? topic.oldest - cursor.next : 0;
    const auto sequence = cursor.next + missed;
    if (sequence >= topic.next) return nullptr;
    return topic.slots[bus_slot(topic, sequence)];
}

extern "C" ASBusSubscription *as_bus_subscribe(ASBus *bus, uint32_t stream_id,
                                                int start_latest) {
    if (!bus || !stream_id) return nullptr;
    std::shared_ptr<BusTopic> topic;
    {
        std::lock_guard<std::mutex> lock(bus->mutex);
        auto found = bus->topics.find(stream_id);
        if (found == bus->topics.end()) return nullptr;
        topic = found->second;
    }
    std::lock_guard<std::mutex> lock(topic->mutex);
    // Eliminate expired cursors before enforcing the subscriber limit.
    auto out = topic->cursors.begin();
    for (auto iter = topic->cursors.begin(); iter != topic->cursors.end(); ++iter) {
        if (!iter->expired()) *out++ = *iter;
    }
    topic->cursors.erase(out, topic->cursors.end());
    if (topic->cursors.size() >= topic->limit) return nullptr;
    try {
        auto cursor = std::make_shared<BusCursor>();
        cursor->next = start_latest ? topic->next : topic->oldest;
        auto subscription = std::unique_ptr<ASBusSubscription>(new ASBusSubscription{topic, cursor});
        topic->cursors.push_back(cursor);
        topic->stats.active_subscribers = static_cast<uint32_t>(topic->cursors.size());
        return subscription.release();
    } catch (...) { return nullptr; }
}

extern "C" void as_bus_unsubscribe(ASBusSubscription *subscription) {
    if (!subscription) return;
    auto topic = subscription->topic;
    {
        std::lock_guard<std::mutex> lock(topic->mutex);
        // Leases keep cursor alive; closed subscription should not stall trim.
        auto cursor = subscription->cursor;
        cursor->next = topic->next;
        bus_trim_consumed(*topic);
    }
    delete subscription;
}

extern "C" ASBusStatus as_bus_poll(ASBusSubscription *subscription, void *buffer,
                                    size_t capacity, ASBusHeader *header,
                                    size_t *bytes, uint64_t *missed) {
    if (!subscription || !header || !bytes || !missed || (!buffer && capacity))
        return ASBUS_INVALID;
    auto topic = subscription->topic;
    std::lock_guard<std::mutex> lock(topic->mutex);
    if (subscription->cursor->leased) return ASBUS_BUSY;
    uint64_t gap = 0;
    auto event = bus_next(*topic, *subscription->cursor, gap);
    if (!event) return topic->closed ? ASBUS_CLOSED : ASBUS_EMPTY;
    *bytes = event->payload.size();
    if (event->payload.size() > capacity) return ASBUS_BUFFER_TOO_SMALL;
    if (!event->payload.empty() && !buffer) return ASBUS_INVALID;
    if (!event->payload.empty()) std::memcpy(buffer, event->payload.data(), *bytes);
    *header = event->header;
    *missed = gap;
    subscription->cursor->next = event->header.sequence + 1;
    if (topic->config.overflow == ASBUS_REJECT_NEWEST) bus_trim_consumed(*topic);
    return ASBUS_OK;
}
