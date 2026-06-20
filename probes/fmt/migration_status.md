# fmt migration status — full-project hybrid coverage

> Status snapshot for the fmt → yelu migration. Covers Phases 0–8.
> Phase log archived in [`doc/worklog/worklog_2026_06.md`](../../doc/worklog/worklog_2026_06.md).
> Current-state overview in [`README.md`](README.md).
>
> **Historical note (2026-06-19):** this is a closed record of the `.ml`→`.yc`
> migration. The legacy OCaml-DSL emitters it links (`main.ml` / `test_main.ml`
> / `compile_error_test.ml`, via `Yelu_emit_main`) were **retired** once the
> `.yc` corpus became the sole source — those links and the `yc_apply`/
> `raw_cmake` counts below are frozen migration history, not the live state.

## Headline (2026-06-08)

**11/11 `.yc` files compile and pass the matrix oracle.**
24/24 cells match. 14→3 raw escapes (by design). git-worktree
hybrid driver with auto-discovered helpers from a 5-line main.json.

## Inventory (vendor/fmt, 1354 lines, 11 cmake files)

| file | lines | migrator (.ml) | migrator (.yc) |
|---|---:|---|---|
| `CMakeLists.txt` | 593 | [`main.ml`](main.ml) | [`main.yc`](main.yc) |
| `test/compile-error-test/CMakeLists.txt` | 276 | [`compile_error_test.ml`](compile_error_test.ml) | [`compile_error_test.yc`](compile_error_test.yc) |
| `test/CMakeLists.txt` | 247 | [`test_main.ml`](test_main.ml) | [`test_main.yc`](test_main.yc) |
| `test/cuda-test/CMakeLists.txt` | 77 | [`cuda_test.ml`](cuda_test.ml) | [`cuda_test.yc`](cuda_test.yc) |
| `test/fuzzing/CMakeLists.txt` | 32 | [`fuzzing.ml`](fuzzing.ml) | [`fuzzing.yc`](fuzzing.yc) |
| `test/static-export-test/CMakeLists.txt` | 30 | [`static_export_test.ml`](static_export_test.ml) | [`static_export_test.yc`](static_export_test.yc) |
| `support/cmake/JoinPaths.cmake` | 28 | — | [`join_paths.yc`](join_paths.yc) |
| `test/gtest/CMakeLists.txt` | 26 | [`gtest.ml`](gtest.ml) | [`gtest.yc`](gtest.yc) |
| `test/find-package-test/CMakeLists.txt` | 17 | [`find_package_test.ml`](find_package_test.ml) | [`find_package_test.yc`](find_package_test.yc) |
| `test/add-subdirectory-test/CMakeLists.txt` | 17 | [`add_subdirectory_test.ml`](add_subdirectory_test.ml) | [`add_subdirectory_test.yc`](add_subdirectory_test.yc) |
| `support/cmake/FindSetEnv.cmake` | 11 | [`find_setenv.ml`](find_setenv.ml) | [`find_setenv.yc`](find_setenv.yc) |

All 11 files have `.yc` concrete-syntax versions. All compile via the parser and pass
the matrix oracle. The `.ml` OCaml DSL versions are retained as reference/source-of-truth.

10 user-defined cmake helper functions — all migrated:
`join`, `set_verbose`, `setup_target`, `add_module_library`,
`add_doc_target`, `expect_compile`, `run_tests`, `add_fmt_test`,
`add_fuzzer`, `join_paths`.

## What the matrix oracle *does* and *doesn't* prove

The fmt matrix harness runs:

```
for cell in (FMT_DOC, FMT_INSTALL, FMT_TEST, FMT_FUZZ, FMT_CUDA_TEST,
             FMT_OS, FMT_MODULE, FMT_SYSTEM_HEADERS, FMT_UNICODE,
             FMT_PEDANTIC, FMT_WERROR, FMT_FUZZ_LINKMAIN) × {ON, OFF}:
    cmake -B vendor-build  -S vendor/fmt              -D<cell>
    cmake -B hybrid-build  -S _out/fmt/yelu/source  -D<cell>
    diff vendor-build/CMakeCache.txt hybrid-build/CMakeCache.txt
```

This is a **configure-time oracle**. The cmake binary parses both
trees, runs the `cmake -B <build> -S <src>` pass, and produces
`CMakeCache.txt`. We diff those two files. That's it.

What this proves:
- Our generated cmake text is syntactically valid cmake.
- Every `set()`, `option()`, `set_verbose()`, `math()`, `string()`,
  `file(READ)`, `try_compile`, etc. produces the same cache entries
  as vendor.
- Every `if`/`else`/`endif` branch fires identically on the same
  inputs.
- The generated CMakeLists is *structurally equivalent at
  configure time* to the vendor source on the host running the
  matrix.

What this does **not** prove:
- That `cmake --build` succeeds. We never compile fmt.
- That the resulting library or test binaries actually run.
- That `ctest` passes.
- That `cmake --install` produces a usable install tree.
- That code gated behind compiler/host conditions we don't hit
  (MSVC, Visual Studio generator, CUDA toolchain, `WIN32`,
  `BUILD_SHARED_LIBS=ON`) emits the right cmake — only that it
  parses if cmake ever enters those branches.

In short: we have proven **the cmake file faithfully describes the
same configure-time state**. We have not proven the project still
builds, tests, or installs correctly through the hybrid sources.
A configure-time oracle is what the matrix can give us cheaply
across 24 option-flips; build/test oracles would need a real
compiler step per cell (24× slower) and would still need a
build-test-install rig per platform.

## Known limitations

### 1. The `raw_cmake` escape — what it is and why we have it

`Yelu_emit_main.raw_cmake "<verbatim cmake text>"` (in
[`src/langs/yelu/yelu_emit_main.ml`](../../src/langs/yelu/yelu_emit_main.ml))
is an emit-time escape hatch. The string is dropped into the
generated `CMakeLists.txt` exactly as written — no IR, no
evaluator, no checker pass touches it.

We added it in Phase 7 because cmake's quoted-string grammar
allows backslash escapes (`\"`, `\\`) and embedded newlines that
our cmake pretty printer (`Lang_cmake_pp.quoted`) wraps with
plain `"..."` *without* escaping inner characters. Strings
containing literal `"`, `\`, or newlines can't always be
round-tripped through a `ystr s → ECmakeSet → pretty-print`
chain.

We use `raw_cmake` once in [`main.ml`](main.ml), for the
WINSDK / netfxpath / `run-msbuild.bat` block: a Windows-only
path that has both backslash-laden absolute paths
(`C:\\Program Files\\...`) and a multi-line bat-file body with
embedded `\"` quotes inside `file(WRITE)`. Those don't fit
through the pp cleanly. raw_cmake copies them verbatim.

The cost of `raw_cmake`:
- **Codegen is correct**: cmake parses the verbatim block exactly
  as it parses vendor's identical lines.
- **No yelu introspection**: the yelu_cmake evaluator can't run
  this block. The checker can't see it. Any future analysis pass
  (typing, dependency extraction, equivalence proofs) treats
  raw_cmake as an opaque void. It's a deliberate downgrade from
  IR to text.
- **Counts as unmodeled surface**: every `raw_cmake` site is a
  pointer to a cmake construct that's worth a typed IR
  constructor in the future, or that we've decided isn't.

Today's one site is **dead code on Linux** (gated on
`FMT_MASTER_PROJECT AND CMAKE_GENERATOR MATCHES "Visual Studio"`).
The matrix never enters it, so we have only codegen verification
of `raw_cmake` — no runtime semantic exercise.

The escape's value isn't its current use; it's that whenever a
future migration hits an unmodel-able construct, there's a
documented path to ship the migration anyway and file the
construct as IR work later.

### 2. Windows-specific code is migrated but never exercised

The migration host is Linux + GCC. Roughly **a third of fmt's
cmake** is gated on Windows / MSVC / Visual Studio conditions:

| guard | what's inside |
|---|---|
| `if (MSVC)` | `PEDANTIC_COMPILE_FLAGS=/W3`, `WERROR_FLAG=/WX`, `target_compile_options /Zc:preprocessor`, `target_compile_options /Zc:__cplusplus /permissive-` for cuda-test, `target_compile_options /utf-8` for unicode-test, `target_compile_definitions _CRT_SECURE_NO_WARNINGS` in gtest, `target_compile_options /bigobj` for format-test, `target_compile_options /Zc:__cplusplus /permissive-` for posix-mock-test |
| `if (CMAKE_GENERATOR MATCHES "Visual Studio")` | the WINSDK / FindSetEnv / `run-msbuild.bat` block (`raw_cmake` escape) |
| `if (NOT CMAKE_GENERATOR STREQUAL "Ninja")` (inside `if MSVC`) | the `add_module_library` BMI / ifc setup with `file(TO_NATIVE_PATH)`, `set_source_files_properties GENERATED ON` |
| `if (NOT DEFINED MSVC_STATIC_RUNTIME AND MSVC)` | foreach over CMAKE_CXX_FLAGS_* with `MATCHES "^(/|-)(MT|MTd)"` + `break()` |
| `if (NOT MSVC_STATIC_RUNTIME)` | posix-mock-test branch |
| `if (NOT WIN32)` | parts of the FMT_PEDANTIC test driver wiring |

What this means concretely:
- The matrix runs on Linux, so `MSVC=OFF`, `WIN32=OFF`, generator
  is `Unix Makefiles` (or `Ninja` on a different machine — also
  not Visual Studio). None of these branches fire during
  `cmake -B build`. They contribute to the file's parse tree only.
- The pretty printer renders these branches. If our codegen
  produced a syntax error inside a Windows branch, the cmake
  parser would catch it (cmake parses the whole file regardless
  of branch taken). The matrix is enough to catch *parse-error*
  bugs.
- The matrix is **not enough** to catch *semantic* bugs inside
  Windows branches: a wrong flag name, a wrong cache variable
  set, a missing argument keyword. Those would only show up on a
  Visual Studio host running cmake configure (and possibly only
  on cmake build).
- We have no Windows CI today. Catching Windows-branch
  regressions depends on running the matrix on a Windows host,
  which we haven't done.

The same caveat applies, more strongly, to the CUDA branch
(`test/cuda-test/CMakeLists.txt`): the matrix doesn't have a CUDA
toolchain, so `enable_language(CUDA)` would either find no
compiler (silently skipped via `check_language(CUDA)` + the
`if (CMAKE_CUDA_COMPILER)` guard) or fail. Either way, the
branch isn't entered. The migration is codegen-only.

### 3. Stubs for find/probe operations

The yelu_cmake evaluator stubs `find_program(... NOTFOUND)`,
`find_package(Threads)` (canned result), and
`try_compile(... FALSE)`. These match fmt's actual behavior *on
this Linux + GCC host*, so the matrix succeeds. On a host where
the stubs and reality diverge (e.g. doxygen *is* installed, so
`find_program(DOXYGEN ...)` would succeed) the matrix would show
mismatches — not because the migration is wrong, but because the
stubs are host-specific.

This is the "per-host vs per-project stubs" gap noted in
[`README.md`](README.md) § "Open issues specific to fmt". It's
not a migration issue; it's an oracle-infrastructure issue.

### 4. `yc_apply` is a soft escape too

`yc_apply (ystr "<cmd>") [args...]` calls a cmake command
without going through a typed IR constructor. It still lives in
the yelu_cmake AST (so the evaluator and emit walk it), but the
command itself is opaque to any typed-IR analysis. The fmt
migration uses `yc_apply` 53 times across the 3 `.ml` files
(35 in main.ml, 10 in test_main.ml, 8 in compile_error_test.ml).

After the `.yc` conversion (Phase 8), the `yc_apply` count in
`main.ml` dropped from ~100 to 35 — the removed ~65 calls were
replaced by typed IR constructors (`configure_file`, `export`,
`add_custom_target`, `get_target_property`, `configure_package_config_file`,
and others). The remaining 35 are almost all ergonomic (typed ctor
exists but call site is cleaner with apply) or genuinely unmodeled
(`set_property CACHE`, `cmake_parse_arguments`, `check_cxx_compiler_flag`,
project-defined functions `set_verbose`/`join`/`setup_target`/
`add_module_library`/`add_doc_target`/`join_paths`, and the
`install`/`export` complex forms).

`yc_apply` is less drastic than `raw_cmake` — it's still one
*command* call with structured arguments. But it shares the
"no semantic introspection" cost.

## Phase log

Full phase-by-phase record (Phases 0–8) archived in
[`doc/worklog/worklog_2026_06.md`](../../doc/worklog/worklog_2026_06.md).
Key milestones:

- **Phase 0–7** (2026-06-04): all 11 files migrated as `.ml` OCaml DSL emits.
  `raw_cmake` escape hatch for the WINSDK block. Matrix: 24/24 cells.
- **Phase 8** (2026-06-08): `.yc` concrete-syntax conversion. All 11 files
  have `.yc` versions. `yc_apply` in main.ml: ~100 → 35. Raw escapes: 14 → 3.
  Auto-discovery by naming convention. Git-worktree hybrid driver.

## What didn't get done (or got de-scoped)

1. **No build / test / install oracle.** See "What the matrix oracle
   doesn't prove" above. Hand-running `cmake --build` and `ctest`
   on the hybrid tree would catch a different class of bug than
   the configure-time cache diff.

2. **No Windows host run.** All MSVC / Visual Studio / WINSDK
   branches are migrated but only parsed by cmake; never
   semantically exercised.

3. **No CUDA host run.** Same caveat as Windows.

4. **`cmake_parse_arguments` still routes through `yc_apply`.** The
   structured grammar (`<options> <one_value> <multi_value>`) was
   estimated at 1–2 days of IR work and de-scoped. The 3 fmt
   callsites work because the emit produces the right text;
   yelu_cmake can't reason about the parsed argument variables.

5. **`FILE_SET CXX_MODULES` in `add_module_library`** is generated
   through `yc_apply (ystr "target_sources") [...]` — no typed IR.
   This is the C++20-modules code path; only enters when
   `FMT_MODULE=ON` and modern compiler + cmake. The matrix touches
   `FMT_MODULE=ON` but the host (cmake 4.3.1, GCC) doesn't trigger
   the FILE_SET branch.

6. **CPack's gitignore-driven source-package logic** went through
   typed IR for the main pieces (`file(STRINGS)`,
   `string(REPLACE)`, `include(CPack)`) but the surface coverage of
   CPack-specific commands (`cpack_add_*`) wasn't tested — fmt
   doesn't use them.

## Related

- [`README.md`](README.md) — fmt probe status, adaptation footprint,
  Shape C lockup footprint table.
- [`main.json`](main.json) — the splice manifest read by
  `yelu hybrid`. Each entry now says `whole_file: true`.
- `yelu hybrid` ([`src/bin/yelu/yelu.ml`](../../src/bin/yelu/yelu.ml))
  — the universal driver.
- [`../../doc/yelu_cmake/hybrid_strategy.md`](../../doc/yelu_cmake/hybrid_strategy.md)
  — strategy doc (cmake-as-assembly, shapes B/C).
- [`../../doc/yelu_cmake/status.md`](../../doc/yelu_cmake/status.md)
  — predictor-wide open work.
- [`../cache_matrix.md`](../cache_matrix.md) — matrix oracle
  methodology.
