# fmt migration plan — full-project hybrid coverage

> Per-project tracking doc for the fmt → yelu migration. Strategy
> framing in [`../../doc/yelu_cmake/hybrid_strategy.md`](../../doc/yelu_cmake/hybrid_strategy.md);
> per-helper pilot status in [`README.md`](README.md).

## Inventory (vendor/fmt, 1354 lines, 11 cmake files)

| file | lines | role |
|---|---:|---|
| `CMakeLists.txt` | 593 | top-level: 12 options, 10 helper fns, all targets, install, CPack |
| `test/compile-error-test/CMakeLists.txt` | 276 | `expect_compile` codegen helper + cmake_parse_arguments + file(WRITE) |
| `test/CMakeLists.txt` | 247 | `add_fmt_test` helper + foreach over names + add_test calls |
| `test/cuda-test/CMakeLists.txt` | 77 | enable_language(CUDA) + cuda_add_executable |
| `test/fuzzing/CMakeLists.txt` | 32 | `add_fuzzer` helper + foreach (already exercised by matrix) |
| `test/static-export-test/CMakeLists.txt` | 30 | static lib export |
| `support/cmake/JoinPaths.cmake` | 28 | `join_paths` function |
| `test/gtest/CMakeLists.txt` | 26 | gtest setup |
| `test/find-package-test/CMakeLists.txt` | 17 | basic find_package consumer |
| `test/add-subdirectory-test/CMakeLists.txt` | 17 | subdir consumer |
| `support/cmake/FindSetEnv.cmake` | 11 | trivial find_program |

10 user-defined helper functions:
`join`, `set_verbose`, `setup_target`, `add_module_library`,
`add_doc_target`, `expect_compile`, `run_tests`, `add_fmt_test`,
`add_fuzzer`, `join_paths`. **Migrated so far: 2** (join +
set_verbose, see [`README.md`](README.md) §
"Hybrid pilot — step 1.a/1.b").

Top commands across all files: `if/endif` (93), `set` (85),
`target_compile_options` (21), `add_fmt_test` (20 calls),
`target_link_libraries` (19), `message` (13), `add_library` (13),
`target_compile_definitions` (12), `option` (12), `foreach`
(11), `function` (10), `target_include_directories` (10).

## Phased plan

Modeled from the pilot's pace: ~1 hour per helper for steps 1.a
(text codegen) + 1.b (build oracle) combined.

| phase | scope | est days | new IR risk |
|---|---|---:|---|
| **1** | Remaining 8 helper functions in main CMakeLists.txt: `setup_target`, `add_module_library`, `add_doc_target`, `add_fmt_test`, `add_fuzzer`, `expect_compile`, `run_tests` + `join_paths` from support/. Each as own `.ml`, spliced in-place. | **2** | Low for most; **`expect_compile` needs `cmake_parse_arguments` modeling** — could grow to 1d on its own |
| **2** | support/ files: `JoinPaths.cmake` + `FindSetEnv.cmake` as whole-file emits. Pattern: `probes/fmt/support/<name>.ml` produces the full `.cmake` file. | **0.5** | None |
| **3** | Small test subdirs: find-package-test, add-subdirectory-test, gtest, static-export-test, fuzzing — each ~20–30 lines. One `.ml` per subdir; manifest.json gains subdir-replacement entries. | **2** | Low |
| **4** | Large test subdirs: test/CMakeLists.txt (20 add_fmt_test calls in foreach) + test/compile-error-test (24 expect_compile callsites generating C++ fragments). | **3** | Medium — exercises any gaps in cmake_parse_arguments / file(WRITE) / string(MAKE_C_IDENTIFIER) eval |
| **5** | test/cuda-test — `enable_language(CUDA)` + `cuda_add_executable`. May need new IR. | **1** | Medium-High |
| **6** | Main CMakeLists.txt by section: preamble (project, min_version, FMT_USE_CMAKE_MODULES gate), options(), target setup, compile-options matrix (GNU/Clang/MSVC × std × warning levels), install + export + configure_package_config + version file, CPack, doc/test gating. | **5–7** | High — CPack surface unknown; FMT_MODULE branch uses FILE_SET CXX_MODULES (modern cmake); install pipeline has many ctors to wire |
| **7** | Shape C lockup: `probes/fmt/project.ml` becomes the whole-project yelu source. raw_cmake escapes for anything not modeled. Matrix oracle still 24/24. | **2** | Low-Medium |

### Totals

|  | optimistic | realistic | pessimistic |
|---|---:|---:|---:|
| **Focused-work days** | 12 | 16 | 22 |
| **Calendar (part-time)** | 3 weeks | 5 weeks | 8 weeks |

## Top risk factors (in order of impact)

1. **`cmake_parse_arguments` modeling.** Used 3× in fmt. Complex
   grammar (`<options> <one_value> <multi_value>` keyword
   classification). Currently routes to Apply (lenient). Real
   modeling would be 1–2 days. **Mitigation**: extend rather than
   fully model — capture enough shape for the 3 callsites we need.

2. **FILE_SET / CXX_MODULES in `add_module_library`.** Modern
   cmake (3.28+). Our IR has `add_library` but not the FILE_SET
   HEADERS / CXX_MODULES sub-surface. **Mitigation**: if not
   modeled by Phase 6, use raw_cmake escape in Shape C; accept
   that this branch isn't yelu-managed.

3. **CPack surface.** Large but largely declarative. Our IR has
   some CPack support (`doc/worklog/worklog_2026_05.md` mentions
   CPack ctors landing in Tier F). **Mitigation**: verify Tier F
   coverage before Phase 6; gaps may need 1–2d.

4. **Compiler probes (`check_*` family).** Used by main CMakeLists
   for FMT_MODULE detection logic. Our stubs are FALSE-direction.
   **Mitigation**: same as the matrix oracle — works as long as
   "stub direction matches reality" (which fmt's existing matrix
   proves). If the build oracle diverges, fix the probe stub
   directionally.

5. **`set_target_properties` / `set_property`.** Used 10× combined.
   IR has TargetProperty fragment but partially complete per
   [`../../doc/yelu_cmake/cmake_vs_normal.md`](../../doc/yelu_cmake/cmake_vs_normal.md).
   **Mitigation**: spot-check coverage before Phase 6; may need
   0.5–1d.

## Recommendation

Don't commit to the whole 16-day plan up-front — the per-phase
ROI tapers off after Phase 4. Phases 1–3 (helpers + support +
small subdirs) are high-confidence, low-cost (~5 days) and
demonstrate the strategy across diverse cmake constructs. **Stop
after Phase 3 to re-assess.** Phases 4–7 are where the unknowns
cluster (`cmake_parse_arguments`, FILE_SET, CPack) and where the
cost-vs-learning ratio inverts.

Concretely: **Phase 1 is the next sensible chunk** — `yelu hybrid`
already supports the splicing pattern; each of the 8 remaining
helpers is a small repeatable exercise of the strategy. ~2 days
total, ~15min per helper plus verification.

## Progress tracker

| phase | status | start | finish | notes |
|---|---|---|---|---|
| 0 (pilot: join + set_verbose) | ✓ | 2026-06-04 | 2026-06-04 | step 1.a + 1.b done; 24/24 cells match |
| 1 (remaining helpers) | not started | — | — | next on deck |
| 2 (support/) | not started | — | — | |
| 3 (small test subdirs) | not started | — | — | DECISION POINT after this |
| 4 (large test subdirs) | not started | — | — | gated on Phase 1 surfacing risks |
| 5 (cuda) | not started | — | — | |
| 6 (main CMakeLists) | not started | — | — | |
| 7 (Shape C lockup) | not started | — | — | |

## Related

- [`README.md`](README.md) — fmt probe status + adaptation footprint
- [`manifest.json`](manifest.json) — splice manifest read by
  `yelu hybrid`
- `yelu hybrid` (src/bin/yelu/yelu.ml) — the universal driver
  that this plan extends one helper at a time
- [`../../doc/yelu_cmake/hybrid_strategy.md`](../../doc/yelu_cmake/hybrid_strategy.md)
  — strategy doc (cmake-as-assembly, shapes B/C, why the
  architecture supports this)
- [`../../doc/yelu_cmake/status.md`](../../doc/yelu_cmake/status.md)
  — predictor-wide open work that might unblock specific phases
