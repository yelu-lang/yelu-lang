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

## Format choice — `.ye` vs `.ml`

After the mixed-format demo (commit `12da517`), every helper has
a choice of source format:

- **`.ye`** — concrete yelu surface syntax. Parsed in-process by
  `Yelu_parse.parse_program_y1`. Tests the language while
  migrating. The parser covers the full 14-theory IR surface (one
  `p_<theory>_command_y1` dispatcher per theory family) but
  individual command shapes have varying coverage. **Preferred
  when feasible.**
- **`.ml`** — OCaml host-builds the IR using ergonomic ctors
  (`yc_function`, `yc_set`, etc.) and emits via `print_cmake`.
  Full IR ergonomics; subprocesses via `dune exec`. **Use when
  the surface parser doesn't cover a construct.**

Per-helper choice. Mixed formats coexist in one manifest. When a
`.ye` attempt fails (parser doesn't recognize a shape), the
fallback is rewriting that helper as `.ml`. Each `.ye` attempt
also surfaces a parser gap we could fix — useful side product.

What's known about parser coverage today:
- ✓ assignment (`X := value`), set, option, unset_cache
- ✓ if/then/else with full cond surface (defined, target,
  str_eq, ver_lt, exists, list_in, and/or, not, etc.)
- ✓ function/macro/apply/foreach/while/break/continue/return
- ✓ string, list, path, file, target, dir, test, property,
  find, install, try, cmake_op command families have
  dedicated dispatchers (specific command shapes vary)
- ⚠ unknown coverage of: `cmake_parse_arguments`,
  `FILE_SET CXX_MODULES`, modern install/export keyword
  patterns, CPack

## Phased plan

Modeled from the pilot's pace: ~1 hour per helper for steps 1.a
(text codegen) + 1.b (build oracle) combined.

The "format" column is a **starting guess** based on each
helper's complexity. Surprises (parser gaps surfacing as `.ye`
parse errors) will shift items toward `.ml`.

| phase | scope | est days | format | new IR risk |
|---|---|---:|---|---|
| **1** | Remaining 8 helper functions: `setup_target`, `add_module_library`, `add_doc_target`, `add_fmt_test`, `add_fuzzer`, `expect_compile`, `run_tests` + `join_paths` from support/. Each spliced in-place. | **2** | mixed: `run_tests` / `add_fmt_test` / `add_fuzzer` / `join_paths` start as `.ye`; `setup_target` / `add_module_library` / `add_doc_target` / `expect_compile` likely `.ml` (complex cmake constructs or unsupported surface) | Low for most; **`expect_compile` needs `cmake_parse_arguments` modeling** — could grow to 1d |
| **2** | support/ files: `JoinPaths.cmake` + `FindSetEnv.cmake` as whole-file emits. | **0.5** | both `.ye` candidates — small, single-function files | None |
| **3** | Small test subdirs: find-package-test, add-subdirectory-test, gtest, static-export-test, fuzzing — each ~20–30 lines. Manifest gains subdir-replacement entries. | **2** | `.ye` preferred; mostly project()/add_executable/target_link_libraries patterns the surface parser covers | Low |
| **4** | Large test subdirs: test/CMakeLists.txt (20 add_fmt_test calls in foreach) + test/compile-error-test (24 expect_compile callsites). | **3** | mostly `.ml`; foreach + helper-call-in-loop patterns are easier to express with OCaml host iteration than yelu surface foreach | Medium — exercises any gaps in cmake_parse_arguments / file(WRITE) / string(MAKE_C_IDENTIFIER) eval |
| **5** | test/cuda-test — `enable_language(CUDA)` + `cuda_add_executable`. | **1** | `.ml` likely; CUDA is niche, may need raw_cmake escape | Medium-High |
| **6** | Main CMakeLists.txt by section: preamble, options(), target setup, compile-options matrix, install + export + version file, CPack, doc/test gating. | **5–7** | sections vary: preamble + options() are `.ye` candidates; target_compile_options matrix and CPack likely `.ml` | High — CPack surface unknown; FMT_MODULE / FILE_SET CXX_MODULES; install pipeline |
| **7** | Shape C lockup: `probes/fmt/project.{ml,ye}` is the whole-project yelu source. raw_cmake escapes for anything not modeled. Matrix oracle still 24/24. | **2** | starts `.ml` (safer for whole-project); convert to `.ye` once parser proven on individual sections | Low-Medium |

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

6. **Surface parser coverage for `.ye` migrations.** New since
   the format-choice section above. Per-helper, attempting `.ye`
   first surfaces concrete parser gaps; falling back to `.ml`
   when it fails costs only minutes per attempt.
   **Mitigation**: budget ~10min per `.ye` attempt + fallback;
   record which command shapes the parser refuses (file separate
   issues against `yelu_parse.ml` as found). The fmt migration
   doubles as a parser coverage test.

   **Parser gaps surfaced so far**:
   - ~~**`foreach IN LISTS X`**~~ — ✓ fixed. p_foreach_y1 gained
     a `LISTS <ident>+` branch emitting `ECmakeForeachInList`.
   - ~~**`set X v PARENT_SCOPE`** — trailing PARENT_SCOPE
     identifier was being slurped as a value.~~ ✓ fixed.
     p_set_command_y1 now recognizes the trailing keyword and
     sets `~parent_scope:true`.
   - **Dynamic target names** (`Target ${var}`) — the target
     command parsers (p_target_command_y1_inner) only accept
     literal identifiers in target slots. fmt's `add_fuzzer`
     uses `${name}` (a function parameter) for every target op.
     Bigger fix than the previous two (cascades through 8 target
     commands); deferred. add_fuzzer landed as `.ml`.

   The discover-fix loop costs ~10–20 min per small gap so far.
   Larger gaps (dynamic-target-name above) get deferred and the
   helper falls back to `.ml`.

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

Within Phase 1, try `.ye` first for each helper (per the format
table above). If parser refuses, fall back to `.ml`. Either way
the splice manifest is the same; the choice only affects the
source file's extension and the toolchain it goes through.

## Progress tracker

| phase | status | start | finish | notes |
|---|---|---|---|---|
| 0 (pilot: join + set_verbose) | ✓ | 2026-06-04 | 2026-06-04 | step 1.a + 1.b done; 24/24 cells match |
| 0+ (mixed-format demo: use_cmake_modules_false.ye) | ✓ | 2026-06-04 | 2026-06-04 | first `.ye` source in manifest alongside `.ml`; 24/24 still match (commit `12da517`) |
| 1 (remaining helpers) | in progress | 2026-06-04 | — | 2/8 done. `join_paths` (`.ye`, after fixing `foreach IN LISTS` + `set ... PARENT_SCOPE` parser gaps). `add_fuzzer` (`.ml`, dynamic-target-name gap surfaced; deferred). 6 remaining. |
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
