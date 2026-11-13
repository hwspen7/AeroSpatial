#include "test_common.h"
#include "aerospatial_runtime.h"
#include <cstdint>
int main() {
    ASNativeAbiInfo info{};
    info.major = 1234;
    REQUIRE(!as_native_abi_info(nullptr, sizeof(info)));
    REQUIRE(!as_native_abi_info(&info, sizeof(info) - 1));
    REQUIRE(info.major == 1234);
    REQUIRE(as_native_abi_info(&info, sizeof(info)));
    REQUIRE(info.struct_size == sizeof(ASNativeAbiInfo));
    REQUIRE(info.major == 1 && info.minor >= 1 && info.reserved == 0);
    const uint64_t expected = AS_NATIVE_FEATURE_RESOURCE_BUDGET |
        AS_NATIVE_FEATURE_CLOCK_QUALITY | AS_NATIVE_FEATURE_PIPELINE_METRICS |
        AS_NATIVE_FEATURE_COVARIANCE_DIAGNOSTICS;
    REQUIRE((info.feature_bits & expected) == expected);
}
