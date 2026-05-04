#!/bin/bash
# Test that yelu step programs produce cmake output semantically
# equivalent to the reference cmake-tutorial via cmake file API.
#
# Usage: Run from project root:
#   bash test/test_yelu_vs_ref.sh [step_number]
#
# Requires: dune build, cmake >= 3.14, python3

set -euo pipefail
cd "$(dirname "$0")/.."

TUTORIAL="vendor/cmake-tutorial"
YELU="_build/default/src/bin/yelu"

# Build all yelu executables
dune build src/bin/yelu/ 2>&1 | tail -1 || true

tmpdir=$(mktemp -d /tmp/yelu_vs_ref.XXXXXX)
trap "rm -rf $tmpdir" EXIT

# Generate yelu cmake output into a project directory.
# assemble <step_num> <dest_dir>
# Copies source files from reference, generates cmake files from yelu.
assemble() {
  local step=$1 dest=$2 ref="$TUTORIAL/step$step"

  # Copy entire reference tree (sources + cmake configs)
  cp -r "$ref/." "$dest/"

  # Overwrite CMakeLists.txt files with yelu output
  # Root CMakeLists.txt
  local root_exe="$YELU/step${step}.exe"
  if [ ! -f "$root_exe" ]; then
    # step8 reuses step7's root (identical in reference)
    root_exe="$YELU/step7.exe"
  fi
  "$root_exe" > "$dest/CMakeLists.txt" 2>/dev/null

  # MathFunctions/CMakeLists.txt (step2+)
  if [ -d "$dest/MathFunctions" ]; then
    local math_exe="$YELU/step${step}_math.exe"
    if [ ! -f "$math_exe" ]; then
      # step9 reuses step8's math (identical in reference)
      math_exe="$YELU/step8_math.exe"
    fi
    "$math_exe" > "$dest/MathFunctions/CMakeLists.txt" 2>/dev/null
  fi

  # Special files
  local special_exe
  special_exe="$YELU/step${step}_table.exe"
  if [ -f "$special_exe" ]; then "$special_exe" > "$dest/MathFunctions/MakeTable.cmake" 2>/dev/null; fi

  special_exe="$YELU/step${step}_ctest.exe"
  if [ -f "$special_exe" ]; then "$special_exe" > "$dest/CTestConfig.cmake" 2>/dev/null; fi

  special_exe="$YELU/step${step}_config.exe"
  if [ -f "$special_exe" ]; then "$special_exe" > "$dest/Config.cmake.in" 2>/dev/null; fi

  special_exe="$YELU/step${step}_multi.exe"
  if [ -f "$special_exe" ]; then "$special_exe" > "$dest/MultiCPackConfig.cmake" 2>/dev/null; fi
}

passed=0
failed=0
skipped=0

run_step() {
  local step=$1
  local ref="$TUTORIAL/step$step"
  local yelu_dir="$tmpdir/yelu_step$step"

  if [ ! -d "$ref" ]; then
    echo "  step$step: SKIP (no reference)"
    skipped=$((skipped + 1))
    return
  fi

  mkdir -p "$yelu_dir"
  assemble "$step" "$yelu_dir"

  echo -n "  step$step: "
  if python3 test/cmake_file_api_cmp.py "$ref" "$yelu_dir" 2>/tmp/yelu_vs_ref_err.log; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    cat /tmp/yelu_vs_ref_err.log >&2
  fi
}

# Run specified step or all steps
if [ $# -ge 1 ]; then
  echo "--- Yelu vs Reference (step $1) ---"
  run_step "$1"
else
  echo "--- Yelu vs Reference (all steps) ---"
  for step in 1 2 3 4 5 6 7 8 9 10 11 12; do
    run_step "$step"
  done
fi

echo ""
echo "Passed: $passed, Failed: $failed, Skipped: $skipped"
[ "$failed" -eq 0 ]
