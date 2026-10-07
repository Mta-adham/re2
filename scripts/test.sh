#!/usr/bin/env bash
# Run the RE2 GoogleTest suite (same set as upstream CI: the slow
# dfa/exhaustive/random tests are excluded). Requires scripts/build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="${ARTEMIS_BUILD_DIR:-build-artemis}"
ctest --test-dir "$BUILD_DIR" -C Release --output-on-failure \
  --parallel "$(nproc 2>/dev/null || echo 4)" -E 'dfa|exhaustive|random'
