# Probes — real-world cmake projects as predictor testbeds

This directory groups the docs around **using real cmake projects to
test and gain-adapt the yelu_cmake predictor**.

## What's a "probe"?

A probe is a real cmake project (fmt, z3, llvm, …) pointed at the
predictor to surface gaps the unit tests can't. Each probe runs two
oracles:

- **Parse-print oracle** ([parse_print_oracle.md](parse_print_oracle.md))
  — `cmake_source → parse.py → Lang_cmake.exp → pp → text`. Does the
  AST round-trip byte-equivalently? Catches printer bugs and parser
  drops.
- **Cache matrix oracle** ([cache_matrix.md](cache_matrix.md))
  — `cmake_source → yc-eval → predicted cache_vars` compared against
  `cmake -DOPT=val → CMakeCache.txt` for each option × {ON, OFF}.
  Catches eval-level fidelity gaps.

Both oracles are diff-based and need cmake on the host. Both are
per-project — each project's gaps are different.

## Layout

```
probes/
  README.md                # this file
  candidates.md            # shortlist of next projects to probe
  cache_matrix.md          # how the matrix probe works (methodology)
  parse_print_oracle.md    # how the parse-print round-trip works
  <project>/               # one folder per project
    README.md              # current status — landing page
    migration_plan.md      # full-project hybrid migration plan + tracker
    <helper>.ml            # per-helper yelu IR (Phase 1+; ad-hoc as needed)
    hybrid_smoke.sh        # build-oracle harness (per project; pattern from fmt)
```

One folder per project. Files inside grow as the probe matures
(spec → migration plan → per-helper yelu IR → hybrid smoke).
Small projects may stay at just README.md.

## How to add a new project probe

1. Skim [candidates.md](candidates.md). Pick one that has a small
   CMakeLists, no exotic find_package web, and configure-time work
   (not just compile-time).
2. Run the parse-print oracle:
   ```sh
   bash tool/cmake_roundtrip/test_corpus.sh /path/to/project
   ```
   Expect mostly OK on small projects; STRUCT failures point at
   specific printer/parser gaps to fix.
3. Build a matrix smoke test, modelled on
   [test_fmt_matrix_smoke.ml](../test/test-runcmake/test_fmt_matrix_smoke.ml):
   - point `<name>_dir` at the project root
   - run `cache_vars.exe` to extract flippable options
   - register `include_loader` + `subdir_loader` from `Cmake_bridge`
   - configure env defaults (`CMAKE_CURRENT_SOURCE_DIR`,
     `CMAKE_INSTALL_PREFIX`, etc.)
4. First run will surface real-only entries. Decide for each:
   - Add to `assumed_found_packages` whitelist? (for known-installed
     packages like Threads)
   - Build a new ECmake* arm? (for unmodeled commands)
   - Accept as a gap? (for cmake-stdlib-coverage limits)
5. Create `probes/<name>/README.md` with current status (see
   [fmt/README.md](fmt/README.md) as a reference — captures probe
   status, project spec, adaptation footprint, hybrid pilot
   results). If migrating to yelu, add a `migration_plan.md`
   (see [fmt/migration_plan.md](fmt/migration_plan.md)).

## Current per-project state

| project | parse-print | cache matrix | adaptation status |
|---|---|---|---|
| [fmt](fmt/) | 11/11 OK | 24/24 cells matched, median 20 | complete; whitelist + stubs added |
| [z3](z3/) | 108/108 OK | not yet built | parse-print only |
| [llvm](llvm/) | 3004/3035 OK (30 pre-existing STRUCT) | not yet built | parse-print only |

## Related docs

- [../doc/yelu_cmake/io_architecture.md](../doc/yelu_cmake/io_architecture.md) —
  the library/runner I/O split that enables both oracles
- [../doc/yelu_cmake/status.md](../doc/yelu_cmake/status.md) — predictor-wide
  open work (cross-cuts all probes)
- [../doc/yelu_cmake/structure.md](../doc/yelu_cmake/structure.md) — fragment
  map showing what's wired vs deferred
