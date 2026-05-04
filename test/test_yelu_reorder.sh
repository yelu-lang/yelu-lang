#!/bin/bash
# Test that reordering independent statements in yelu produces
# semantically equivalent cmake output (verified via cmake file API).
#
# Usage: Run from project root:
#   bash test/test_yelu_reorder.sh
#
# Requires: cmake >= 3.14, python3

set -euo pipefail
cd "$(dirname "$0")/.."

TUTORIAL_DIR="vendor/cmake-tutorial/step1"
tmpdir=$(mktemp -d /tmp/yelu_reorder_test.XXXXXX)
trap "rm -rf $tmpdir" EXIT

# Original cmake (step1 order)
cat > "$tmpdir/original.cmake" << 'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(Tutorial VERSION 1.0)
set(CMAKE_CXX_STANDARD 11 )
set(CMAKE_CXX_STANDARD_REQUIRED ON )
configure_file(TutorialConfig.h.in TutorialConfig.h)
add_executable(Tutorial tutorial.cxx)
target_include_directories(Tutorial PUBLIC "${PROJECT_BINARY_DIR}")
CMAKE

# Reordered cmake (swap sets, move configure_file after add_executable)
cat > "$tmpdir/reordered.cmake" << 'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(Tutorial VERSION 1.0)
set(CMAKE_CXX_STANDARD_REQUIRED ON )
set(CMAKE_CXX_STANDARD 11 )
add_executable(Tutorial tutorial.cxx)
configure_file(TutorialConfig.h.in TutorialConfig.h)
target_include_directories(Tutorial PUBLIC "${PROJECT_BINARY_DIR}")
CMAKE

# Semantically different cmake (changed standard)
cat > "$tmpdir/different.cmake" << 'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(Tutorial VERSION 1.0)
set(CMAKE_CXX_STANDARD 17 )
set(CMAKE_CXX_STANDARD_REQUIRED ON )
configure_file(TutorialConfig.h.in TutorialConfig.h)
add_executable(Tutorial tutorial.cxx)
target_include_directories(Tutorial PUBLIC "${PROJECT_BINARY_DIR}")
CMAKE

echo "--- Test 1: Reordered should be EQUIVALENT ---"
python3 test/cmake_file_api_cmp.py "$TUTORIAL_DIR" \
  "$tmpdir/original.cmake" "$tmpdir/reordered.cmake"
echo ""

echo "--- Test 2: Different standard should be DIFFERENT ---"
if python3 test/cmake_file_api_cmp.py "$TUTORIAL_DIR" \
  "$tmpdir/original.cmake" "$tmpdir/different.cmake" 2>/dev/null; then
  echo "ERROR: Should have detected difference!"
  exit 1
else
  echo "(correctly detected as different)"
fi

echo ""
echo "All reorder tests passed."
