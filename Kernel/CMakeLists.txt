cmake_minimum_required(VERSION 3.16)
project(AeroSpatialNative LANGUAGES CXX)
include(CTest)
find_package(Threads REQUIRED)
set(NATIVE_ROOT "${CMAKE_CURRENT_LIST_DIR}")
add_library(aerospatial_native STATIC
    "${NATIVE_ROOT}/src/Geometry/geometry.cpp"
    "${NATIVE_ROOT}/src/Geometry/orientation.cpp"
    "${NATIVE_ROOT}/src/Geometry/filter.cpp"
    "${NATIVE_ROOT}/src/Geometry/frames.cpp"
    "${NATIVE_ROOT}/src/Geometry/slerp.cpp"
    "${NATIVE_ROOT}/src/Geometry/transform.cpp"
    "${NATIVE_ROOT}/src/Geometry/batch.cpp"
    "${NATIVE_ROOT}/src/Geometry/wire.cpp"
    "${NATIVE_ROOT}/src/Runtime/qos.cpp"
    "${NATIVE_ROOT}/src/Geometry/camera.cpp"
    "${NATIVE_ROOT}/src/Estimation/calibration.cpp"
    "${NATIVE_ROOT}/src/Estimation/tracking.cpp"
    "${NATIVE_ROOT}/src/Estimation/pose.cpp"
    "${NATIVE_ROOT}/src/Estimation/inertial.cpp"
    "${NATIVE_ROOT}/src/Runtime/runtime_metrics.cpp"
    "${NATIVE_ROOT}/src/Video/h264.cpp"
    "${NATIVE_ROOT}/src/Video/access_unit.cpp"
    "${NATIVE_ROOT}/src/Runtime/work_queue.cpp"
    "${NATIVE_ROOT}/src/Runtime/memory.cpp"
    "${NATIVE_ROOT}/src/Runtime/executor.cpp"
    "${NATIVE_ROOT}/src/Estimation/fusion.cpp"
    "${NATIVE_ROOT}/src/Estimation/adaptive.cpp"
    "${NATIVE_ROOT}/src/Bus/bus_core.cpp"
    "${NATIVE_ROOT}/src/Bus/bus_consumer.cpp"
    "${NATIVE_ROOT}/src/Bus/bus_lease.cpp")
target_include_directories(aerospatial_native PUBLIC "${NATIVE_ROOT}/include" PRIVATE "${NATIVE_ROOT}")
target_compile_features(aerospatial_native PUBLIC cxx_std_17)
target_link_libraries(aerospatial_native PUBLIC Threads::Threads)
if(MSVC)
    target_compile_options(aerospatial_native PRIVATE /W4)
else()
    target_compile_options(aerospatial_native PRIVATE -Wall -Wextra -Wpedantic)
endif()
function(aerospatial_add_tool target source)
    add_executable(${target} "${NATIVE_ROOT}/Tools/${source}")
    target_include_directories(${target} PRIVATE "${NATIVE_ROOT}")
    target_link_libraries(${target} PRIVATE aerospatial_native)
endfunction()
aerospatial_add_tool(aerospatial-native-probe probe.cpp)
aerospatial_add_tool(aerospatial-wire-probe wire_probe.cpp)
aerospatial_add_tool(aerospatial-qos-probe qos_probe.cpp)
if(BUILD_TESTING)
    target_compile_definitions(aerospatial_native PRIVATE AEROSPATIAL_TEST_HOOKS)
    set(NATIVE_TEST_ROOT "${NATIVE_ROOT}/../NativeTests")
    set(NATIVE_TEST_GROUP_Bus bus bus_concurrency bus_resources bus_budget_race bus_faults bus_soak)
    set(NATIVE_TEST_GROUP_Geometry geometry orientation filter frames slerp transform batch wire camera)
    set(NATIVE_TEST_GROUP_Estimation calibration tracking estimation adaptive fusion)
    set(NATIVE_TEST_GROUP_Video h264 access_unit h264_real access_dual)
    set(NATIVE_TEST_GROUP_Runtime qos runtime_metrics work_queue memory executor work_lease)
    foreach(group IN ITEMS Bus Geometry Estimation Video Runtime)
        foreach(name IN LISTS NATIVE_TEST_GROUP_${group})
            add_executable(test_${name} "${NATIVE_TEST_ROOT}/${group}/test_${name}.cpp")
            target_include_directories(test_${name} PRIVATE "${NATIVE_TEST_ROOT}/Common" "${NATIVE_TEST_ROOT}")
            target_link_libraries(test_${name} PRIVATE aerospatial_native)
            if(name STREQUAL "h264_real")
                target_compile_definitions(test_${name} PRIVATE AEROSPATIAL_FIXTURE_DIR="${NATIVE_ROOT}/../Fixtures")
            endif()
            add_test(NAME native_${name} COMMAND test_${name})
        endforeach()
    endforeach()
endif()

option(AEROSPATIAL_BUILD_BUS_BENCHMARK "Build bus benchmark executable" OFF)
if(AEROSPATIAL_BUILD_BUS_BENCHMARK)
    aerospatial_add_tool(aerospatial-bus-bench bus_benchmark.cpp)
endif()

option(AEROSPATIAL_BUILD_BENCHMARKS "Build native benchmark executable" OFF)
if(AEROSPATIAL_BUILD_BENCHMARKS)
    aerospatial_add_tool(aerospatial-bench benchmark.cpp)
endif()

option(AEROSPATIAL_BUILD_ESTIMATION_BENCHMARK "Build inertial estimator benchmark" OFF)
if(AEROSPATIAL_BUILD_ESTIMATION_BENCHMARK)
    aerospatial_add_tool(aerospatial-estimation-bench estimation_benchmark.cpp)
endif()

option(AEROSPATIAL_BUILD_WORK_BENCHMARK "Build bounded native task queue benchmark" OFF)
if(AEROSPATIAL_BUILD_WORK_BENCHMARK)
    aerospatial_add_tool(aerospatial-work-bench work_benchmark.cpp)
endif()
