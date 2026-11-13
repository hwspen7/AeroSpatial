#ifndef AEROSPATIAL_TEST_COMMON_H
#define AEROSPATIAL_TEST_COMMON_H
#include <cstdio>
#include <cstdlib>
#define REQUIRE(condition) do { \
    if (!(condition)) { \
        std::fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #condition); \
        std::abort(); \
    } \
} while (0)
#endif
