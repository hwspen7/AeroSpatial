#include "bus_internal.hpp"
#include <new>

extern "C" ASBusStatus as_bus_acquire(ASBusSubscription *subscription,
                                       ASBusLease **lease, uint64_t *missed) {
    if (!subscription || !lease || !missed) return ASBUS_INVALID;
    auto topic = subscription->topic;
    std::lock_guard<std::mutex> lock(topic->mutex);
    if (subscription->cursor->leased) return ASBUS_BUSY;
    uint64_t gap = 0;
    auto event = bus_next(*topic, *subscription->cursor, gap);
    if (!event) return topic->closed ? ASBUS_CLOSED : ASBUS_EMPTY;
    auto *result = new (std::nothrow) ASBusLease{event, topic, subscription->cursor};
    if (!result) return ASBUS_LIMIT_REACHED;
    subscription->cursor->leased = true;
    subscription->cursor->next = event->header.sequence + 1;
    *missed = gap;
    *lease = result;
    // Keep the leased message alive even when another writer overwrites the slot.
    if (topic->config.overflow == ASBUS_REJECT_NEWEST) bus_trim_consumed(*topic);
    return ASBUS_OK;
}

extern "C" const void *as_bus_lease_data(const ASBusLease *lease, size_t *size,
                                          ASBusHeader *header) {
    if (!lease || !size || !header) return nullptr;
    *size = lease->event->payload.size();
    *header = lease->event->header;
    return *size ? lease->event->payload.data() : nullptr;
}

extern "C" void as_bus_release(ASBusLease *lease) {
    if (!lease) return;
    {
        std::lock_guard<std::mutex> lock(lease->topic->mutex);
        lease->cursor->leased = false;
        if (lease->topic->config.overflow == ASBUS_REJECT_NEWEST)
            bus_trim_consumed(*lease->topic);
    }
    delete lease;
}
