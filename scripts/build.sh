#!/usr/bin/env bash
# Compile RE2 (library, tests, benchmark) in Release mode into build-artemis/.
# First run downloads pinned Abseil/GoogleTest/Benchmark; later runs are incremental.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="${ARTEMIS_BUILD_DIR:-build-artemis}"
GENERATOR=()
if command -v ninja >/dev/null 2>&1; then GENERATOR=(-G Ninja); fi

cmake -S scripts -B "$BUILD_DIR" "${GENERATOR[@]}" -D CMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" --config Release --parallel
