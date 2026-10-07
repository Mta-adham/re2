# Self-contained build wrapper for Artemis: fetches the pinned versions of
# Abseil, GoogleTest and Benchmark (matching MODULE.bazel) and then builds
# RE2 with its tests and benchmarks against them. No system packages needed.

cmake_minimum_required(VERSION 3.22)
project(RE2Artemis CXX)

include(FetchContent)

if(DEFINED ENV{ARTEMIS_DEPS_DIR})
  set(FETCHCONTENT_BASE_DIR "$ENV{ARTEMIS_DEPS_DIR}")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Link the MinGW runtime statically so test/benchmark binaries never load a
# mismatched libstdc++-6.dll from elsewhere on PATH (e.g. Git's /mingw64/bin),
# which makes Windows show a blocking "entry point not found" dialog.
if(MINGW)
  add_link_options(-static)
endif()

set(ABSL_PROPAGATE_CXX_STD ON CACHE BOOL "" FORCE)
set(ABSL_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(ABSL_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)

set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)

set(BENCHMARK_ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(BENCHMARK_ENABLE_GTEST_TESTS OFF CACHE BOOL "" FORCE)
set(BENCHMARK_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(BENCHMARK_ENABLE_WERROR OFF CACHE BOOL "" FORCE)

FetchContent_Declare(absl
  URL https://github.com/abseil/abseil-cpp/archive/refs/tags/20250814.1.tar.gz
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_Declare(googletest
  URL https://github.com/google/googletest/archive/refs/tags/v1.17.0.tar.gz
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_Declare(benchmark
  URL https://github.com/google/benchmark/archive/refs/tags/v1.9.4.tar.gz
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_MakeAvailable(absl googletest benchmark)

enable_testing()
set(RE2_BUILD_TESTING ON CACHE BOOL "" FORCE)
set(RE2_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/.. re2)
