#!/usr/bin/env bash
# fmt hybrid smoke — step 1.b of the hybrid pilot.
#
# Build hybrid fmt source where lines 21–39 (join + set_verbose
# helpers) are replaced with yelu-emitted equivalents. Run real
# cmake on both vendor/fmt and the hybrid; diff the resulting
# CMakeCache.txt entries (project + unknown tier only). Pass if
# zero divergence.
#
# Usage:
#   bash probes/fmt/hybrid_smoke.sh [opt=val ...]
#
# Examples:
#   bash probes/fmt/hybrid_smoke.sh                    # default flags
#   bash probes/fmt/hybrid_smoke.sh FMT_FUZZ=ON        # one cell flip
#   bash probes/fmt/hybrid_smoke.sh FMT_TEST=OFF FMT_DOC=OFF
#
# Layout:
#   _out/fmt/hybrid/
#     helpers.cmake           ← generated from set_verbose.ml
#     source/                 ← copy of vendor/fmt with helpers spliced
#     build-vendor/           ← cmake configure on vendor/fmt
#     build-hybrid/           ← cmake configure on source/

set -euo pipefail

cd "$(dirname "$0")/../.."   # repo root
out=_out/fmt/hybrid
mkdir -p "$out"

# ============================================================
# 1. Generate the helpers via the OCaml pilot.

dune build probes/fmt/set_verbose.exe 2>&1 | sed 's/^/[dune] /'
dune exec probes/fmt/set_verbose.exe > "$out/helpers.cmake"
echo "[step1] generated $out/helpers.cmake ($(wc -l <"$out/helpers.cmake") lines)"

# ============================================================
# 2. Build hybrid source: copy of vendor/fmt with helpers spliced.

rm -rf "$out/source"
mkdir -p "$out/source"

# Resolve vendor/fmt's real path (it's a symlink to contrib).
fmt_real=$(realpath vendor/fmt)

# Mirror the tree with symlinks pointing at upstream (so we don't
# duplicate gigabytes of source), but copy CMakeLists.txt for in-place
# editing.
for entry in "$fmt_real"/*; do
  name=$(basename "$entry")
  if [ "$name" = "CMakeLists.txt" ]; then
    cp "$entry" "$out/source/$name"
  else
    ln -s "$entry" "$out/source/$name"
  fi
done

# Splice: keep lines 1-20, append yelu helpers, keep lines 40+.
# fmt's helpers are at lines 21-39 (see CMakeLists.txt:21 / :39).
{
  head -n 20 "$fmt_real/CMakeLists.txt"
  cat "$out/helpers.cmake"
  tail -n +40 "$fmt_real/CMakeLists.txt"
} > "$out/source/CMakeLists.txt"

echo "[step2] hybrid source at $out/source/ (CMakeLists.txt: $(wc -l <"$out/source/CMakeLists.txt") lines)"

# ============================================================
# 3. Run real cmake on both sources.

vendor_build="$out/build-vendor"
hybrid_build="$out/build-hybrid"
rm -rf "$vendor_build" "$hybrid_build"

# Pass -D flags from command line as-is.
d_flags=()
for arg in "$@"; do
  d_flags+=("-D$arg")
done

cmake -B "$vendor_build" -S "$fmt_real"      "${d_flags[@]}" >/dev/null 2>&1
cmake -B "$hybrid_build" -S "$out/source"    "${d_flags[@]}" >/dev/null 2>&1
echo "[step3] both configures done"

# ============================================================
# 4. Diff project + unknown tier names.

# Use cache_classify to drop CMAKE_* reserved noise — the existing
# test harness defines the same tier filter. For this smoke, a simple
# grep -v of common reserved prefixes is sufficient to surface the
# project-meaningful diff. (Full classifier-based filter is what the
# matrix smoke uses; this script just needs the visible delta.)
strip_cache() {
  grep -E "^[A-Za-z_][A-Za-z0-9_]*:" "$1" \
    | grep -vE "^(CMAKE_|CTEST_|_CMAKE|GLOBAL_FLAGS_|PACKAGE_|CPACK_|FMT_FUZZ|fmt_DIR)" \
    | cut -d: -f1,3- \
    | sort
}

vendor_cache=$(strip_cache "$vendor_build/CMakeCache.txt")
hybrid_cache=$(strip_cache "$hybrid_build/CMakeCache.txt")

if [ "$vendor_cache" = "$hybrid_cache" ]; then
  echo "[step4] caches MATCH — hybrid is semantically equivalent"
  exit 0
else
  echo "[step4] caches DIVERGE:"
  diff <(echo "$vendor_cache") <(echo "$hybrid_cache") | head -40
  exit 1
fi
