#!/usr/bin/env bash
# Per-cell consume/check script (the "who depends on this lib, and how do we
# exercise it" declaration — hacked as a script for now). The SAME script runs
# against both the vanilla-cmake and yelu-cmake builds of libfmt; the harness
# compares its (exit, stdout) across the two sides. Identical output ⇒ the two
# builds are equivalent from a downstream consumer's point of view.
#
#   argv[1] / $BE_BLD : the build dir holding libfmt.so + dev symlinks
#   $BE_SRC           : the configured source tree (fmt headers under include/)
#
# It builds a tiny program against the freshly-built libfmt and runs it. Output
# must be deterministic (no timestamps / addresses) so cross-side comparison is
# meaningful.
set -euo pipefail
BLD="${1:-$BE_BLD}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/consume.cpp" <<'CPP'
#include <fmt/format.h>
int main() {
  // exercise the compiled library (fmt::format lives in the built .so, not
  // header-only), with a fully deterministic payload
  fmt::print("{}-{}-{:04x}\n", fmt::format("{}", 6 * 7), "ok", 3405);
  return 0;
}
CPP

c++ -std=c++11 -I"$BE_SRC/include" "$work/consume.cpp" \
    -L"$BLD" -lfmt -Wl,-rpath,"$BLD" -o "$work/consume"
"$work/consume"
