#include "include/aerospatial_runtime.h"
#include <cstring>

extern "C" int as_native_abi_info(ASNativeAbiInfo *out, size_t capacity) {
    if (!out || capacity < sizeof(ASNativeAbiInfo)) return 0;
    ASNativeAbiInfo info{};
    info.struct_size = static_cast<uint32_t>(sizeof(ASNativeAbiInfo));
    info.major = 1;
    info.minor = 1;
    info.feature_bits = AS_NATIVE_FEATURE_RESOURCE_BUDGET |
                        AS_NATIVE_FEATURE_CLOCK_QUALITY |
                        AS_NATIVE_FEATURE_PIPELINE_METRICS |
                        AS_NATIVE_FEATURE_COVARIANCE_DIAGNOSTICS;
    std::memcpy(out, &info, sizeof(info));
    return 1;
}
