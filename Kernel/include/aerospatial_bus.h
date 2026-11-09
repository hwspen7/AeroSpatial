#ifndef AEROSPATIAL_BUS_H
#define AEROSPATIAL_BUS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Each producer uses monotonic time from its declared clock domain.
   The bus preserves timestamps: it never silently converts clock domains. */
typedef struct ASBus ASBus;
typedef struct ASBusSubscription ASBusSubscription;
typedef struct ASBusLease ASBusLease;

typedef enum {
    ASBUS_OK = 0,
    ASBUS_INVALID = 1,
    ASBUS_EMPTY = 2,
    ASBUS_BACKPRESSURE = 3,
    ASBUS_TOO_LARGE = 4,
    ASBUS_BUFFER_TOO_SMALL = 5,
    ASBUS_TIME_REGRESSION = 6,
    ASBUS_BUSY = 7,
    ASBUS_LIMIT_REACHED = 8
} ASBusStatus;

typedef enum {
    ASBUS_OVERWRITE_OLDEST = 1, /* observation streams */
    ASBUS_REJECT_NEWEST = 2    /* important retained notifications */
} ASBusOverflow;

typedef enum {
    ASBUS_QUALITY_VALID = 1u << 0,
    ASBUS_QUALITY_SIMULATED = 1u << 1,
    ASBUS_QUALITY_CLOCK_ESTIMATED = 1u << 2,
    ASBUS_QUALITY_LOW_CONFIDENCE = 1u << 3,
    ASBUS_QUALITY_STALE = 1u << 4,
    ASBUS_QUALITY_UPSTREAM_GAP = 1u << 5
} ASBusQuality;

enum {
    ASBUS_HEAD = 1, ASBUS_TELEMETRY = 2,
    ASBUS_VIDEO = 3, ASBUS_PERCEPTION = 4, ASBUS_DIAGNOSTIC = 5
};

typedef struct {
    uint32_t max_topics;              /* 1..64 */
    uint32_t max_subscribers_per_topic; /* 1..128 */
} ASBusConfig;

typedef struct {
    uint32_t stream_id;         /* nonzero */
    uint32_t capacity;          /* 1..4096 events */
    uint32_t max_payload_bytes; /* 1..8 MiB per event */
    uint32_t overflow;          /* ASBusOverflow */
} ASBusTopicConfig;

typedef struct {
    uint64_t timestamp_ns;  /* monotonic within stream and clock domain */
    uint64_t sequence;      /* assigned by bus, must be 0 on publish */
    uint64_t trace_id;      /* optional correlation ID */
    uint32_t stream_id;
    uint32_t clock_domain;  /* nonzero; constant within each topic */
    uint32_t quality_flags;
    uint32_t kind;          /* application-defined type within topic */
} ASBusHeader;

typedef struct {
    uint64_t published;
    uint64_t overwritten;
    uint64_t rejected;
    uint64_t invalid;
    uint64_t retained_bytes;
    uint64_t high_water_bytes;
    uint64_t next_sequence;
    uint32_t retained_events;
    uint32_t active_subscribers;
} ASBusTopicStats;

/* Opaque handles. Subscribers may outlive the parent bus, and drain retained events.
   Destroying the same handle concurrently with its use is not supported. */
ASBus *as_bus_create(const ASBusConfig *config);
void as_bus_destroy(ASBus *bus);
ASBusStatus as_bus_add_topic(ASBus *bus, ASBusTopicConfig config);
ASBusStatus as_bus_publish(ASBus *bus, ASBusHeader header,
                           const void *payload, size_t payload_bytes);
ASBusStatus as_bus_stats(ASBus *bus, uint32_t stream_id, ASBusTopicStats *stats);

/* oldest=0 starts with retained data; oldest=1 starts after the newest event. */
ASBusSubscription *as_bus_subscribe(ASBus *bus, uint32_t stream_id, int start_latest);
void as_bus_unsubscribe(ASBusSubscription *subscription);

/* A copy read has no retained pointers. BUFFER_TOO_SMALL preserves the cursor
   and returns the exact required byte count in payload_bytes. */
ASBusStatus as_bus_poll(ASBusSubscription *subscription, void *buffer,
                        size_t buffer_capacity, ASBusHeader *header,
                        size_t *payload_bytes, uint64_t *missed);

/* Native zero-copy fan-out. A lease protects its payload through overwrites.
   One outstanding lease per subscriber; release it promptly. At most
   max_subscribers_per_topic external leases can retain additional payloads. */
ASBusStatus as_bus_acquire(ASBusSubscription *subscription, ASBusLease **lease,
                           uint64_t *missed);
const void *as_bus_lease_data(const ASBusLease *lease, size_t *size,
                              ASBusHeader *header);
void as_bus_release(ASBusLease *lease);

#ifdef __cplusplus
}
#endif
#endif
