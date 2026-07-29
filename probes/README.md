# Probes — real-world cmake projects as predictor testbeds

This directory groups the docs around **using real cmake projects to
test and gain-adapt the yelu_cmake predictor**.

> **Probing a new project as a handoff-mode agent?** Read
> [`PROBE_CHARTER.md`](PROBE_CHARTER.md) first — mission, boundaries (don't touch
> yelu_cmake infra), the pause protocol, and the learn → plan → discuss → execute
> workflow. This README is the *mechanics*; the charter is *how to behave*.

## What's a "probe"?

A probe is a real cmake project (fmt, z3, llvm, …) pointed at the
predictor to surface gaps the unit tests can't. A mature probe can exercise
three verification layers:

- **Parse-print oracle** (completed 2026-05-31, see [worklog](../doc/worklog/worklog_2026_06.md))
  — `cmake_source → parse.py → Lang_cmake.exp → pp → text`. Does the
  AST round-trip byte-equivalently? Catches printer bugs and parser
  drops.
- **`.yc` corpus compile gate** — parse, wellform-check, and emit every
  migrated source. This is part of `dune test` for fmt.
- **Hybrid semantic matrix** ([cache_matrix.md](cache_matrix.md)) — compare
  upstream CMake with a yelu-generated worktree for each option × {ON, OFF}.
  The completed fmt probe checks three channels per cell: `CMakeCache.txt`,
  File API codemodel-v2, and CTest definitions. This is a *configure-time*
  oracle.
- **Build-level equivalence** (`build_equiv`, Level 7 in
  [framework/testing.md](../doc/framework/testing.md)) — actually *build* the
  project from vanilla-cmake vs yc-emitted cmake and compare artifacts, exported
  symbols, bytes, and a downstream consume script. The fmt probe has a fixture
  at [test/fixtures/build_equiv/fmt/](../test/fixtures/build_equiv/fmt/README.md)
  (byte-identical `libfmt`). Structured as a per-cell matrix; the intended
  endpoint is a **three-way** cell — vanilla cmake / yc / ycn.

The parse-print, hybrid, and build-level oracles need CMake on the host. All
layers are per-project — each project's gaps are different.

## Layout

```
probes/
  README.md                # this file
  candidates.md            # shortlist of next projects to probe
  cache_matrix.md          # how the matrix probe works (methodology)
  (parse-print oracle completed; see doc/worklog/worklog_2026_06.md)
  <project>/               # one folder per project
    README.md              # current status — landing page
    migration_status.md    # full-project hybrid migration status report
    <path>.yc              # yelu source mirroring the upstream CMake path
    main.json               # driver configuration (per project; read by `yelu hybrid`)
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
   results). If migrating to yelu, add a `migration_status.md`
   (see [fmt/migration_status.md](fmt/migration_status.md)).

## Current per-project state

| project | parse-print | `.yc` corpus | semantic matrix | status |
|---|---|---|---|---|
| [fmt](fmt/) | 11/11 OK | 11/11 compile | 24/24 × cache + codemodel + CTest | complete first whole-project probe |
| [json](json/) | — | 1/1 compile | 18/18 × cache + codemodel + CTest | **first pass complete** (v3.12.0, root-only); 5 gaps recorded (J1–J5) — see [`README.md`](json/README.md) |
| [z3](z3/) | 108/108 OK | — | not yet built | parse-print only |
| [llvm](llvm/) | 3004/3035 OK (30 pre-existing STRUCT) | — | not yet built | parse-print only |

## Related docs

- [module system and loader architecture](../doc/framework/module_system.md) —
  the library/runner I/O split that enables both oracles
- [project status](../doc/status.md) — predictor-wide
  open work (cross-cuts all probes)
- [../doc/yelu_cmake/ir/structure.md](../doc/yelu_cmake/ir/structure.md) — fragment
  map showing what's wired vs deferred
