cmake_minimum_required(VERSION 3.16)
project(AeroSpatialNative LANGUAGES CXX)
include(CTest)
set(NATIVE_ROOT "${CMAKE_CURRENT_LIST_DIR}")
add_library(aerospatial_native STATIC
    "${NATIVE_ROOT}/geometry.cpp"
    "${NATIVE_ROOT}/orientation.cpp"
    "${NATIVE_ROOT}/filter.cpp"
    "${NATIVE_ROOT}/frames.cpp"
    "${NATIVE_ROOT}/slerp.cpp"
    "${NATIVE_ROOT}/transform.cpp"
    "${NATIVE_ROOT}/batch.cpp"
    "${NATIVE_ROOT}/bus_core.cpp"
    "${NATIVE_ROOT}/bus_consumer.cpp"
    "${NATIVE_ROOT}/bus_lease.cpp")
target_include_directories(aerospatial_native PUBLIC "${NATIVE_ROOT}/include")
target_compile_features(aerospatial_native PUBLIC cxx_std_17)
if(MSVC)
    target_compile_options(aerospatial_native PRIVATE /W4)
else()
    target_compile_options(aerospatial_native PRIVATE -Wall -Wextra -Wpedantic)
endif()
add_executable(aerospatial-native-probe "probe.cpp")
target_link_libraries(aerospatial-native-probe PRIVATE aerospatial_native)
if(BUILD_TESTING)
    foreach(name geometry orientation filter frames slerp transform batch bus bus_concurrency)
        add_executable(test_${name} "../NativeTests/test_${name}.cpp")
        target_link_libraries(test_${name} PRIVATE aerospatial_native)
        add_test(NAME native_${name} COMMAND test_${name})
    endforeach()
endif()

option(AEROSPATIAL_BUILD_BUS_BENCHMARK "Build bus benchmark executable" OFF)
if(AEROSPATIAL_BUILD_BUS_BENCHMARK)
    add_executable(aerospatial-bus-bench "bus_benchmark.cpp")
    target_link_libraries(aerospatial-bus-bench PRIVATE aerospatial_native)
endif()

option(AEROSPATIAL_BUILD_BENCHMARKS "Build native benchmark executable" OFF)
if(AEROSPATIAL_BUILD_BENCHMARKS)
    add_executable(aerospatial-bench "benchmark.cpp")
    target_link_libraries(aerospatial-bench PRIVATE aerospatial_native)
endif()
