---
name: feedback-cmake-install-prefix
description: Always pass --prefix to cmake --install; never touch system dirs
metadata:
  type: feedback
---

When running `cmake --install` for verification, **always** pass
`--prefix <local-temp-dir>` (e.g. a dir under `/tmp`). Never run a bare
`cmake --install`, which falls back to `CMAKE_INSTALL_PREFIX` (often
`/usr/local`) and would write into system directories.

**Why:** the standard yelu test harness stops at `cmake` *configure* — it
does not normally run the install (or build/run) stage. Running
`cmake --install` is fine when configure-stage verification isn't enough
(e.g. checking that install(TARGETS) artifacts land in the right per-kind
destinations — done 2026-06-13 for the install_targets shape-4 fix), but it
must be sandboxed to a throwaway prefix so nothing system-level is affected.

**How to apply:** `cmake --install <build> --prefix "$PWD/inst"` into a
`/tmp` working dir; inspect with `find inst`. Same spirit as
[[feedback-dune-sandbox]] — keep verification side-effect-free.
