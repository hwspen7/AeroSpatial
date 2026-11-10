#ifndef AEROSPATIAL_MEMORY_H
#define AEROSPATIAL_MEMORY_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ASMemoryPool ASMemoryPool;
typedef struct ASMemoryLease ASMemoryLease;
typedef struct {
    uint64_t live_bytes;
    uint64_t high_water_bytes;
    uint64_t allocated_leases;
    uint64_t rejected;
} ASMemoryStats;

/// Fixed aggregate payload budget. One native copy is made on insertion;
/// retaining a lease does not copy. Lease data is immutable for its lifetime.
/// Destroying the pool prevents further insertion but existing leases survive.
ASMemoryPool *as_memory_pool_create(size_t maximum_bytes, size_t maximum_payload_bytes);
void as_memory_pool_destroy(ASMemoryPool *pool);
ASMemoryLease *as_memory_pool_copy(ASMemoryPool *pool, const uint8_t *bytes, size_t length);
ASMemoryLease *as_memory_lease_retain(const ASMemoryLease *lease);
void as_memory_lease_release(ASMemoryLease *lease);
const uint8_t *as_memory_lease_data(const ASMemoryLease *lease, size_t *length);
int as_memory_pool_stats(const ASMemoryPool *pool, ASMemoryStats *out);
#ifdef __cplusplus
}
#endif
#endif
