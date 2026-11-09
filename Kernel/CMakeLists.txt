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
    "${NATIVE_ROOT}/wire.cpp"
    "${NATIVE_ROOT}/qos.cpp"
    "${NATIVE_ROOT}/camera.cpp"
    "${NATIVE_ROOT}/calibration.cpp"
    "${NATIVE_ROOT}/tracking.cpp"
    "${NATIVE_ROOT}/pose.cpp"
    "${NATIVE_ROOT}/inertial.cpp"
    "${NATIVE_ROOT}/runtime_metrics.cpp"
    "${NATIVE_ROOT}/h264.cpp"
    "${NATIVE_ROOT}/adaptive.cpp"
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
add_executable(aerospatial-wire-probe "wire_probe.cpp")
add_executable(aerospatial-qos-probe "qos_probe.cpp")
target_link_libraries(aerospatial-qos-probe PRIVATE aerospatial_native)
target_link_libraries(aerospatial-wire-probe PRIVATE aerospatial_native)
if(BUILD_TESTING)
    target_compile_definitions(aerospatial_native PRIVATE AEROSPATIAL_TEST_HOOKS)
    foreach(name geometry orientation filter frames slerp transform batch bus bus_concurrency bus_resources bus_budget_race bus_faults bus_soak wire qos camera calibration tracking runtime_metrics h264 estimation adaptive)
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

option(AEROSPATIAL_BUILD_ESTIMATION_BENCHMARK "Build inertial estimator benchmark" OFF)
if(AEROSPATIAL_BUILD_ESTIMATION_BENCHMARK)
    add_executable(aerospatial-estimation-bench "estimation_benchmark.cpp")
    target_link_libraries(aerospatial-estimation-bench PRIVATE aerospatial_native)
endif()
