# fmt — yc-eval probe + option-matrix observation report

> **Source**: workflow `fmt-yc-eval-probe` (run `wcu6hr40t`, 2026-06-01).
> Probed fmt's root CMakeLists with 31 parallel agents: 1 inventory,
> 15 yc-eval coverage probes, 14 real-cmake option-matrix runs, 1
> synthesis. Total: ~848k subagent tokens, ~3 minutes wall-clock.
>
> **Status (2026-06-03): SUPERSEDED — pre-implementation snapshot.**
> This report identified what fmt's CMakeLists would need from a real
> yc-eval probe. That probe has since been built and the matrix
> closed: 24 cells, real-only=0, mismatched=0, pred-only=0, median
> matched 20 (see [`matrix_infra.md`](matrix_infra.md) for the
> infrastructure, [`status.md`](status.md) for follow-ups).
>
> Most "would need" gaps below are now filled (find_program /
> find_package(Threads) / try_compile stubs in
> [yelu_cmake_find.ml](../../src/langs/yelu/fragments/yelu_cmake_find.ml),
> [yelu_cmake_try.ml](../../src/langs/yelu/fragments/yelu_cmake_try.ml);
> include() recursion + cmake stdlib path, add_subdirectory recursion
> via subdir_loader, return() bridge). The "Top 3 oracle tests to
> add" recommendation at § 4 is fully realized as
> `test_fmt_matrix_smoke.ml`.
>
> Kept as a historical record of how the gap was originally scoped.

## 1. fmt's option declarations

| Name | Default | Message | Gating impact |
|---|---|---|---|
| `FMT_DOC` | `${FMT_MASTER_PROJECT}` | Generate the doc target. | Gates `add_doc_target()` helper (find_program doxygen/mkdocs, custom commands). Medium. |
| `FMT_INSTALL` | `${FMT_MASTER_PROJECT}` | Generate the install target. | Gates all `install()`, `export()`, `configure_package_config_file`, CPack source-package, pkgconfig generation. **High** — entire packaging block. |
| `FMT_TEST` | `${FMT_MASTER_PROJECT}` | Generate the test target. | Gates `add_subdirectory(test)` — entire test tree. **High**. |
| `FMT_FUZZ` | `OFF` | Generate the fuzz target. | Gates `add_subdirectory(test/fuzzing)` AND adds `FMT_FUZZ` compile definition; flips on two extra cache vars (`FMT_FUZZ_LINKMAIN`, `FMT_FUZZ_LDFLAGS`). Medium. |
| `FMT_CUDA_TEST` | `OFF` | Generate the cuda-test target. | Triggers `enable_language(CUDA)` probe. Medium (toolchain-sensitive). |
| `FMT_OS` | `ON` | Include OS-specific APIs. | Conditional `target_sources(fmt PRIVATE src/os.cc)` vs `target_compile_definitions(... FMT_OS=0)`. **High** — directly rewires the library. |
| `FMT_MODULE` | `${FMT_USE_CMAKE_MODULES}` | Build a module library. | Drives `add_module_library()` with `FILE_SET TYPE CXX_MODULES`, Clang `.pcm`/`.o` pipeline, MSVC `/interface`. **High** — major C++20 module branch. |
| `FMT_SYSTEM_HEADERS` | `OFF` | Expose headers with marking them as system. | Pass-through `SYSTEM` flag on include dirs. Low. |
| `FMT_UNICODE` | `ON` | Enable Unicode support. | Compile-definition pass-through; MSVC `/utf-8`. Low–medium. |
| `FMT_PEDANTIC` | `OFF` | Enable extra warnings and expensive tests. | Activates the large GNU/Clang/MSVC `PEDANTIC_COMPILE_FLAGS` blocks with version-gated extensions. Medium. |
| `FMT_WERROR` | `OFF` | Halt the compilation with an error on compiler warnings. | Appends `-Werror`/`/WX` to flags. Low. |

Note: four defaults reference other variables (`${FMT_MASTER_PROJECT}`, `${FMT_USE_CMAKE_MODULES}`) — these are computed earlier in the script, so eval must already resolve top-level expression defaults to capture realistic behavior.

---

## 2. yc-eval coverage by command

Sorted: worst quality first, then by approx_count descending. **Priority-ordered fix list.**

| Command (count) | IR ctor | Helper | Eval quality | Gap summary |
|---|---|---|---|---|
| `set_verbose` (7) | *(none)* | *(none)* | ❌ none | Not a real cmake command — fmt-local helper function defined in fmt's CMakeLists (wraps cache vars). Will not be reached unless user-defined functions are recognized; currently no IR ctor and would crash eval. |
| `include` (7) | `ECmakeInclude` | `yc_include` | ⚠️ partial | Handler appends file path to `env.includes` only; never loads/processes the module, drops `optional` flag. No recursive eval of included scripts. |
| `foreach` (6) | `ECmakeForeach` (+3 variants) | `yc_foreach` | ⚠️ partial | Plain `foreach` and `RANGE` are full; `ECmakeForeachZip` and `ECmakeForeachInList` are stubs (one iteration, empty bindings). |
| `add_library` (5) | `ECmakeAddLibrary` | `add_lib` | ⚠️ partial | `sources` arg evaluated then discarded (`_sources`); `EXCLUDE_FROM_ALL` not in IR. Target name+kind recorded via `declare_target`, but inline sources aren't attached. |
| `set` (60) | `ESetVar` (core) | `yc_set` | ✅ full | — |
| `if` (30) | `ECmakeIfStmt` | `yif` / `yifthen` | ✅ full | No elseif chain ctor (must desugar to nested `else_`); cond eagerly evaluated; branches lazy. |
| `endif` (30) | *(folded into `ECmakeIfStmt`)* | — | ✅ full | Block terminator absorbed at parse time. Non-issue. |
| `option` (11) | `ECmakeOption` | `yc_option` | ✅ full | Value restricted to `EBool`/`EString`/`EVar`; richer expressions would fall through to `None`. |
| `message` (8) | `ECmakeMessage` | `yc_message` | ✅ full | — |
| `target_compile_options` (7) | `ECmakeTargetCompileOptions` | `compile_opts` | ✅ full | `before` flag dropped in eval (no prepend semantics). |
| `target_compile_definitions` (6) | `ECmakeTargetCompileDefinitions` | `compile_defs` | ✅ full | — |
| `endforeach` (6) | *(folded into `ECmakeForeach`)* | — | ✅ full | Block terminator absorbed at parse time. |
| `function` (5) | `ECmakeFunction` | `yc_function` | ✅ full | Paired with `ECmakeApply` for dynamic-scope call semantics; `Return_function` unwind handled. |
| `endfunction` (5) | *(folded into `ECmakeFunction`)* | — | ✅ full | Block terminator. |
| `target_compile_features` (4) | `ECmakeTargetCompileFeatures` | `compile_feats` | ✅ full | Minor: helper lacks `yc_` prefix convention. |

**The most impactful gap to close first is `add_library`'s dropped `sources`**, because fmt declares 5 libraries and every one of them attaches sources at construction time (e.g., `add_library(fmt ${FMT_SOURCES})`); without storing them, downstream `install(TARGETS)` / `target_sources` / file-set introspection can't see the full target shape, and any yc-eval prediction of fmt's library composition will silently disagree with real cmake. Fixing this is a small IR change (add a `sources` field to the target record + call `add_target_sources` in the eval arm) but unlocks correct end-to-end shape for the entire library-building portion of fmt.

---

## 3. Option matrix observations from real cmake

All 7 tested options configured cleanly (`cmake_exit = 0`) for both ON and OFF. **No errors, no defaults lost on round-trip.** The observed value always matched the requested value.

### Pivot: side-effects per option

| Option | ON side-effects | OFF side-effects | Notable |
|---|---|---|---|
| `FMT_FUZZ` | **+`FMT_FUZZ_LINKMAIN:BOOL=ON`**, **+`FMT_FUZZ_LDFLAGS:STRING=`** | none | **Only option that gates additional cache entries.** Both new vars live inside `if(FMT_FUZZ)` in the top-level CMakeLists. |
| `FMT_CUDA_TEST` | none (CUDA probe runs: `Looking for a CUDA compiler - NOTFOUND`, non-fatal) | none | Triggers compiler probe with side effects in non-FMT cache namespace, not in `FMT_*`. |
| `FMT_OS` | none | none | Despite rewiring `target_sources` vs `target_compile_definitions`, no cache var moves — the effect is on the `fmt` target's property bag, invisible in CMakeCache.txt. |
| `FMT_SYSTEM_HEADERS` | none | none | Pure pass-through to include-dir SYSTEM flag. |
| `FMT_UNICODE` ON only | none (but full FMT_* default set + `FMT_DEBUG_POSTFIX=d`, `FMT_CMAKE_DIR`, `FMT_INC_DIR`, `FMT_LIB_DIR`, `FMT_PKGCONFIG_DIR`, `FMT_IS_TOP_LEVEL=ON` observed) | none | Extras enumerated for ON were the standard FMT_* and packaging-dir cache vars present in every configure — *not* causally tied to FMT_UNICODE. |
| `FMT_PEDANTIC` | triggers `HAVE_FNO_EXCEPTIONS_FLAG` compiler check (non-FMT cache) | none | Compiler-probe side effects only. Status line echoes `-- FMT_PEDANTIC: ON/OFF`. |
| `FMT_WERROR` | none | none | Independent boolean. |

### Non-obvious behaviors

- **`FMT_FUZZ` is the only option observed to gate sibling FMT_* cache entries.** This is the one case where a yc-eval cache-oracle test could miss state if it only models the toggled var.
- **`FMT_CUDA_TEST=ON` is silent on missing toolchain.** cmake logs `NOTFOUND` and proceeds — no error. A naive correctness oracle would expect either success-with-target or failure; the real behavior is success-without-target.
- **`FMT_OS=OFF` produces zero cache delta** despite materially changing the library (sources removed, `FMT_OS=0` compile-definition added). All effects are on target properties, not cache. This means cache-only oracles will completely miss the FMT_OS regression surface.
- **`FMT_PEDANTIC=ON` introduces `HAVE_FNO_EXCEPTIONS_FLAG`** in cache (compiler-probe side effect). Not in `FMT_*` namespace, so easy to overlook.
- **Cache enumeration for FMT_UNICODE=ON happens to include packaging-dir vars** (`FMT_CMAKE_DIR`, `FMT_LIB_DIR`, etc.) — these are always present, not causally linked to FMT_UNICODE. Report's "extra_cache_observed" list is over-inclusive there.

---

## 4. Recommended next steps

### Top 3 yc-eval gaps to fix (impact-ordered)

1. **`add_library` sources attachment** — add `sources : (visibility * expr) list` to the target record (or call `add_target_sources` from `ECmakeAddLibrary`'s eval arm). One IR field + ~5-line eval edit; unlocks correct library-shape modeling for every fmt-class project. Without this, no oracle can compare library composition.
2. **`include` actual module loading** — currently bookkeeping-only. To handle fmt's `include(GNUInstallDirs)`, `CheckCXXCompilerFlag`, `JoinPaths`, `FindSetEnv`, `CMakePackageConfigHelpers`, `CPack`, the evaluator must resolve, parse, and recursively eval the included file (with module-path search and optional-flag handling). Larger landing (~50-200 LOC) but blocks ~7 fmt include sites + every cmake-helper-using project.
3. **`foreach` ZIP_LISTS / IN LISTS** — promote the two stub eval arms to real iteration. fmt uses 6 foreach sites; if any of them use IN LISTS (very common in target/source enumeration), yc-eval silently runs them once with empty bindings, producing wrong results downstream. Small landing per variant (~20 LOC each, follow `ECmakeForeach` template).

### Top 3 option-matrix oracle tests to add

1. **`FMT_FUZZ` ON/OFF** — assert presence/absence of `FMT_FUZZ_LINKMAIN` and `FMT_FUZZ_LDFLAGS` in predicted cache. This is the only fmt option with observable cache side-effects, so it's the highest-signal oracle.
2. **`FMT_OS` ON/OFF target-property oracle** (not cache oracle) — `test_yelu_cache_oracle.ml` would need extension to inspect predicted target property bags. Tests that yc-eval correctly toggles `target_sources(fmt PRIVATE src/os.cc)` ↔ `target_compile_definitions(... FMT_OS=0)`. The cache is silent here; this catches a real semantic divergence.
3. **`FMT_CUDA_TEST=ON` with no CUDA toolkit** — assert configure succeeds (exit 0) and no cuda-test target is materialized. Prevents a regression where yc-eval would treat the CUDA probe as fatal.

### Surprises

- **`add_library` is classified partial, not full.** The probe revealed `sources` is evaluated for side-effects then thrown away — easy to miss in a casual code read because `declare_target` is called.
- **`set_verbose` is not a cmake command** — it's a fmt-defined helper function. Counting it as a 7-call "command shape" in the inventory mislabels it; the real gap is "user-defined function dispatch through `ECmakeApply`," which IS implemented. So if `ECmakeFunction`/`ECmakeApply` are working end-to-end on parsed fmt, `set_verbose` will just work too — the ❌ in the table is misleadingly pessimistic.
- **`option`'s value field is type-restricted to `EBool|EString|EVar`**. Fine for fmt (all defaults are bool literals or `${FMT_MASTER_PROJECT}` vars), but a fragile contract — any future generator-expression default would silently fail.
- **`include` partial-vs-full classification matters more than it looks** because fmt's compiler-detection (CheckCXXCompilerFlag), install-dir layout (GNUInstallDirs), and packaging (CPack) all live behind `include()`. End-to-end yc-eval of fmt without real include loading will be approximately empty of the cross-cutting setup that gates everything else.

---

## 5. Honest caveats

- **Root-only inventory.** Only fmt's top-level `CMakeLists.txt` was scanned. The `test/`, `test/fuzzing/`, `support/cmake/` (JoinPaths, FindSetEnv), and `src/` subdirectories were not inventoried. Real total command counts and gating logic are higher.
- **No yc-eval end-to-end run on fmt.** This report classified each *command* in isolation against the yc-eval IR. fmt's actual top-level script was not parsed and run through `yelu_cmake_eval`; doing so would surface missing IR ctors (e.g., `cmake_parse_arguments`, `file(READ)`, `file(STRINGS)`, `execute_process`, `configure_file`, `add_custom_command`, `list(APPEND)`, `string(REPLACE/REGEX)`, `math(EXPR)`, `cmake_minimum_required`, `cmake_policy`, `include_guard`, `find_program`, `set_property(CACHE ...)`, `set_target_properties`, `export`, `install(EXPORT)`, `configure_package_config_file`, `write_basic_package_version_file`) — none of which were probed here.
- **No yc-eval-vs-real-cmake comparison.** Section 3 reports real cmake observations only. The comparison ("yc-eval predicts FMT_FUZZ_LINKMAIN appears when FMT_FUZZ=ON, real cmake agrees") is left for the main session to wire up after the gaps in section 4 land.
- **No 2-D option interactions.** Each flip was tested independently against an otherwise-default baseline. Combinations like `FMT_TEST=ON ∧ FMT_FUZZ=ON ∧ FMT_MODULE=ON` were not exercised. fmt's `FMT_MASTER_PROJECT`-defaulted options (`FMT_DOC`, `FMT_INSTALL`, `FMT_TEST`) were also never probed with `FMT_MASTER_PROJECT=OFF` (i.e., as-subdirectory), which is the common consumer case.
- **No build/run phase.** Only `cmake` configure was invoked. Compilation, link, and test-run were not exercised; any option that breaks build but not configure (likely candidates: `FMT_WERROR`, `FMT_PEDANTIC`) is unreported.
- **Compiler-probe cache side effects under-enumerated.** `extra_cache_observed` listed only `FMT_*`-namespace deltas; `HAVE_FNO_EXCEPTIONS_FLAG`, CUDA-probe artifacts, etc. are noted in `notes` but not structured.
