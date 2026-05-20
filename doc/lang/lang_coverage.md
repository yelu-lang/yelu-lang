# Yelu Language Coverage Plan

> **Snapshot note (2026-05-20).** The detailed test-suite tables
> below were maintained during the cmake 3.28 → 4.3 transition and
> the pre-retirement IR era. They remain accurate as a **coverage
> map** — what test directories are tractable, which commands hit
> which testing level, what is blocked on `cmake_policy` (Y11) —
> but specific test counts and "X / Y done" numbers may lag the
> code by a few weeks. See `../project_overview.md` for current
> per-suite totals (~1,010 unit tests; 729/729 Bar #3-lite round-
> trip; 50/50 `make runcmake-yelu`; etc.).

## Current State

Runtime: cmake 4.3.1 (`/usr/bin/cmake`, Kitware apt).

| Axis                      | Metric                                     | Done               | Ceiling   | Notes                                                                                     |
| ------------------------- | ------------------------------------------ | ------------------ | --------- | ----------------------------------------------------------------------------------------- |
| **Test depth**            | text unit tests                            | ~1,010             | unbounded | full `dune test` total; pre-retirement number was 266 (72+194) |
| **Test depth**            | script compat tests                        | 64 / ~67           | ~67       | cmake 4.3 unblocked GET, newline, RegexEmptyMatch, KnownComponents                        |
| **Test depth**            | script-pair tests                          | 50 / ~65           | ~65       | 12 command groups; remaining gaps blocked                                                 |
| **Test depth**            | configure tests                            | 23 / ~30           | ~30       | Properties, try_compile, FetchContent, export                                             |
| **Test depth**            | build-level tests                          | 26 / ~30 tractable | ~30       | 11 CMakeCommands + 15 Group 2/3/5; `target_link_libraries` + SubDir/SubDirSpaces blocked  |
| **Test depth**            | file-api tests (steps 1–12)                | 12 / 12 ✓          | 12        | Full codemodel-v2 binding match ✓                                                         |
| **Command breadth**       | commands at `build` level                  | ~15                | ~20       | all `target_*` + `add_compile_*`; ALIAS/OBJECT/MODULE libs; gap: `target_link_libraries`  |
| **Command breadth**       | commands at `script-pair` level            | ~15                | ~20       | all scripting core; gap: `cmake_policy` (Y11)                                             |
| **Command breadth**       | commands with any test                     | ~60                | ~70       | `text`-only commands: `find_*`, `install`, `file`, genex                                  |
| **Benchmark suites**      | `Tests/CMakeOnly/`                         | 12 / 12 ✓          | 12        | all tractable dirs done                                                                   |
| **Benchmark suites**      | `Tests/CMakeCommands/`                     | 11 / 12            | 12        | `target_link_libraries` deferred                                                          |
| **Benchmark suites**      | `Tests/RunCMake/` compat                   | 64 / ~67           | ~67       | cmake 4.3 unblocked 3 tests                                                               |
| **Benchmark suites**      | `Tests/RunCMake/` pairs                    | 50 / ~65           | ~65       | all tractable dirs done; `get_filename_component` pair todo                               |
| **Benchmark suites**      | `Tests/` Group 2/3/5 build                 | 15 / ~26 tractable | ~26       | next: ObjectLibrary/Transitive (re-verify 4.3), StringFileTest (Sc_regex_quote)           |
| **Benchmark suites**      | Tutorial V2 cmake-check / yelu-check       | 11 / 11 ✓          | 11        | both 11/11 ✓                                                                              |
| **Language completeness** | commands fully pipelined (AST→yelu→tested) | ~50                | ~70       | gaps: `cmake_policy`; `cmake_language`/`block`/`cmake_path` yelu layer ✓                  |
| **Language completeness** | commands AST-only or stubs                 | ~5                 | —         | `cmake_policy` partial stub; `cmake_pkg_config` not started                               |

---

## Summary

The strongest axes are **benchmark suite coverage** (CMakeOnly and RunCMake both near ceiling) and **scripting depth** (script-pair tests cover all tractable command dirs). The weakest axis is **build-level breadth**: 26 tests cover the common patterns but Groups 2–5 of `Tests/` still have ~5 tractable directories to add. The single biggest unlocker is `cmake_policy` (Y11) — it unblocks CMP0140 (`return(PROPAGATE)`), CMP0124 (`foreach` scoping), CMP0186 (regex empty match), and several blocked RunCMake dirs.

### Command breadth by group

| Group                 | Commands                                                                                                                                                                                                                                                                                                                                                           | Highest test level       |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------ |
| Tutorial (steps 1–12) | `cmake_minimum_required`, `project`, `set`/`unset`, `option`, `if`, `include`, `configure_file`, `add_executable`, `add_library`, `add_subdirectory`, `target_include_directories`, `target_link_libraries`, `target_compile_definitions`/`features`/`options`, `add_custom_command`, `enable_testing`/`add_test`, `set_tests_properties`, `set_target_properties` | `text` / `file-api`      |
| Properties            | `set_property`, `get_property`/`get_target_property`, `set_target_properties`, `define_property`, `add_custom_target`, `add_dependencies`, `target_precompile_headers`                                                                                                                                                                                             | `configure`              |
| Scripting             | `function`/`macro`, `message`, `math`, `foreach`, `while`/`break`/`continue`, `return`, `list`, `string`, `separate_arguments`, `include_guard`, `get_filename_component`                                                                                                                                                                                          | `script` / `script-pair` |
| Find / package        | `find_library`, `find_path`/`file`/`program`, `find_package`, `FetchContent`                                                                                                                                                                                                                                                                                       | `text` / `configure`     |
| File / process        | `file` (15 subcommands), `execute_process`, `configure_package_config_file`, `write_basic_package_version_file`                                                                                                                                                                                                                                                    | `text` / `configure`     |
| Install / export      | `install`, `export`, `add_library(IMPORTED)`                                                                                                                                                                                                                                                                                                                       | `configure`              |
| Compile               | `try_compile` (new source form), `try_run`                                                                                                                                                                                                                                                                                                                         | `configure` / `text`     |
| Directory commands    | `add_compile_definitions`, `add_compile_options`, `add_link_options`, `link_directories`                                                                                                                                                                                                                                                                           | `build`                  |
| Target commands       | `target_link_options`, `target_compile_definitions`, `target_compile_options`, `target_link_directories`, `target_compile_features`, `target_sources`, `target_include_directories`                                                                                                                                                                                | `build`                  |
| Expressions           | Generator expressions `$<…>` (`yelu_genex` + `yge`)                                                                                                                                                                                                                                                                                                                | `text`                   |

### Command breadth by testing level

| Level         | Commands                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `build`       | `add_compile_definitions`, `add_compile_options`, `add_link_options`, `link_directories`, `target_link_options`, `target_compile_definitions`, `target_compile_options`, `target_link_directories`, `target_compile_features`, `target_sources`, `target_include_directories` (via `Tests/CMakeCommands/`, 11/12; `target_link_libraries` deferred); also `POSITION_INDEPENDENT_CODE`, ALIAS targets, OBJECT/MODULE/INTERFACE libs, `add_custom_command` (via Group 2/3 tests: PositionIndependentTargets, AliasTarget, CxxOnly, CompileDefinitions, TargetName, Simple, LinkLine, LinkLineOrder, OutName, LibName, LinkStatic) |
| `configure`   | `add_custom_command`, `set_property`, `get_property`, `define_property`, `add_custom_target`, `add_dependencies`, `target_precompile_headers`, `try_compile`, `file(RELATIVE_PATH)`, `export`, `configure_package_config_file`, `write_basic_package_version_file`, `add_library(IMPORTED)`, `FetchContent`                                                                                                                                                                                                                                                                                                                     |
| `script-pair` | `set`/`unset`, `if`, `function`/`macro`, `message`, `math`, `foreach`, `while`/`break`/`continue`, `return`, `list`, `string`, `separate_arguments`, `variable_watch`, `cmake_path`, `cmake_language`                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `script`      | `include` (negative-path variants with stderr check)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `file-api`    | `cmake_minimum_required`, `project`, `add_executable`, `add_library`, `target_include_directories`, `target_link_libraries`, `target_compile_definitions`/`features`/`options`, `add_custom_command`, `add_subdirectory` (steps 1–12)                                                                                                                                                                                                                                                                                                                                                                                           |
| `text`        | `cmake_minimum_required`, `project`, `option`, `include`, `configure_file`, `add_executable`, `add_library`, `target_*`, `find_*`, `install`, `file` (ops), `execute_process`, `try_run`, `block`, `cmake_path`, `include_guard`, generator expressions                                                                                                                                                                                                                                                                                                                                                                         |

### Incomplete commands

| Command            | State            | Blocker              |
| ------------------ | ---------------- | -------------------- |
| `cmake_policy`     | partial AST stub | Y11 — design blocked |
| `cmake_pkg_config` | not started      | cmake 4.x only       |

---

## Gaps

### Trackable — no language blocker

| Item                                       | Detail                                                                                                                                                                             |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `target_link_libraries` CMakeCommands test | 182 lines, 5 subdirs; uses `GenerateExportHeader` + `cmake_policy(PUSH/POP)` — consider `Yc_apply` workaround for policy or implement Y11 first                                   |
| `get_filename_component` yelu pair         | Compat passing (KnownComponents, exit-0); yelu pair not yet written                                                                                                                |
| `StringFileTest`                           | `string(REGEX QUOTE)` available in cmake 4.3; needs `Sc_regex_quote` in AST + PP + yelu layer                                                                                     |
| `CompileOptions` → `check_build_pair`      | Was written as `check_build_yelu` workaround; cmake 4.3 available — upgrade to `check_build_pair`                                                                                  |
| `ObjectLibrary/Transitive` subdir          | Dropped for cmake 3.28 OBJECT INTERFACE compat; re-verify on 4.3 and re-add if passing                                                                                             |
| `foreach-all-test` yelu pair               | Upstream uses ITEMS-before-LISTS; PP emits LISTS-first — extend PP or add direct pair using inline cmake                                                                           |
| `function` RunCMake dir                    | `CMAKE_CURRENT_FUNCTION` tests use `list(SUBLIST)`; runtime is now 4.3 — re-check if tractable                                                                                     |

### Blocked — `cmake_policy` (Y11)

Design pass needed before touching code. See `lang_design.md` policy section.

Unlocks: CMP0186 (regex empty match), CMP0140 (`return(PROPAGATE)`), CMP0124 (`foreach` scoping), `try_compile` policy variants, `PolicyScope` build test.

| Blocked item                    | Detail                                                                                              |
| ------------------------------- | --------------------------------------------------------------------------------------------------- |
| `cmake_policy` command          | Partial AST stub only; no yelu node or compiler support                                             |
| `string/RegexEmptyMatch` pair   | Compat ✓ (CMP0186 NEW default in 4.1+); yelu pair needs policy preamble                            |
| `include` CMP0146/CMP0148 pairs | Deprecated FindCUDA/FindPython behavior under policy — require real cmake modules + policy state    |
| `include` ParentVariable*       | `CMAKE_PARENT_LIST_FILE` tracking through include chains — needs multi-file test fixture infra      |
| `foreach` ZIP_LISTS scoping     | CMP0124 loop-variable scoping (NEW vs OLD after loop exits)                                         |
| `return(PROPAGATE …)`           | CMP0140 NEW required                                                                                |
| `try_compile` policy variants   | CMP0056/0066/0067/0128/0137/0210                                                                    |

### Permanently out of scope

| Category                             | Reason                                                                |
| ------------------------------------ | --------------------------------------------------------------------- |
| `GenerateExportHeader` tests         | `CompatibleInterface`, `ExportImport`, `InterfaceLibrary` — cmake module not in yelu |
| `SubDir` / `SubDirSpaces`            | Hardcodes CTest path in `string(FIND ... "SubDir/Executable" ...)`    |
| `SubDirSpaces`                       | Same SubDir blocker                                                   |
| `EmptyLibrary`                       | cmake 4.3 still rejects header-only `add_library(test test.h)`        |
| `Complex`                            | `include_regular_expression("^…")` — no yelu node                    |
| `GeneratorExpression` suite          | cmake's own genex regression suite; `file(GENERATE)` not in yelu     |
| RunCMake `CMP*` dirs (60+)           | Policy/compat tests, error-case only                                  |
| RunCMake `include_guard`             | All scripts use `add_subdirectory`                                    |
| RunCMake `include` ParentVariable*   | Multi-file fixture infra needed                                       |
| RunCMake CTest dirs                  | Require live CTest environment                                        |
| RunCMake configure-only dirs         | Need `cmake -S -B` + compiler                                         |
| RunCMake external tools              | `ClangTidy`, `Cppcheck`, `Autogen_*` — non-cmake binaries             |
| Groups 7–11 (`Tests/`)               | cmake infra, exotic compilers, Find modules, platform-specific        |

---

## Details

### Command Coverage Legend

Pipeline layers and checkpoints:

| Column        | File                                                      | What "✓" means                                        |
| ------------- | --------------------------------------------------------- | ----------------------------------------------------- |
| **cmake AST** | `src/langs/cmake/lang_cmake.ml`                           | Typed constructor exists with all fields (not a stub) |
| **utils**     | `src/langs/cmake/lang_cmake_utils.ml`                     | Ergonomic constructor with optional-argument defaults |
| **yelu AST**  | `src/langs/yelu/yelu_cmake.ml` + `src/langs/yelu/yelu_cmake_emit.ml` | Typed yelu node + emit case (pre-retirement: `lang_yelu.ml` + `lang_yelu_compile.ml`) |
| **tests**     | see level key below                                       | Highest testing level reached                         |

Testing levels — see [`cmake/comparison.md`](cmake/comparison.md) for full definitions and PL vocabulary.

`—` = absent, `✓` = complete, `~` = partial, `stub` = bare constructor no fields.

---

### cmake Test Suite Taxonomy

`yelu/vendor/cmake/Tests/` contains ~313 test directories grouped by tractability.

#### Group 1 — Done

| Directory              | Structure                           | Status                                         |
| ---------------------- | ----------------------------------- | ---------------------------------------------- |
| `Tests/CMakeOnly/`     | Full CMakeLists.txt, NONE compiler  | ✓ 12/12 done (`file-api`); `MajorVersionSelection` uses concrete instantiation (no gersemi string check); `CheckSymbolExists`/`CheckCXXCompilerFlag` not tractable (need C compiler) |
| `Tests/RunCMake/`      | Per-command `.cmake` snippets, NONE | ✓ 64 compat + 50 pairs done                    |
| `Tests/CMakeCommands/` | 12 subdirs, one command each, ~50 L | ✓ 11/12 done; `target_link_libraries` deferred |

#### Group 2 — New tractable, all done (small, focused, C/CXX)

One CMakeLists.txt, ≤100 lines, no cmake module dependencies.

| Directory                    | Lines | Primary feature                                                             | Note                                                                                                                                                     |
| ---------------------------- | ----- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Simple`                     | 17    | basic exe + static lib                                                      | ✓ done                                                                                                                                                   |
| `LinkLine`                   | 13    | link order preservation                                                     | ✓ done (`yc_link_libraries`)                                                                                                                             |
| `LinkLineOrder`              | 37    | deep link order without dep info                                            | ✓ done                                                                                                                                                   |
| `OutName`                    | 6     | `OUTPUT_NAME`, `PREFIX`, `SUFFIX` properties                                | ✓ done                                                                                                                                                   |
| `LibName`                    | 35    | `LIBRARY_OUTPUT_PATH` / `EXECUTABLE_OUTPUT_PATH`                            | ✓ done (`if(UNIX)` emitted unconditionally)                                                                                                              |
| `AliasTarget`                | 72    | `add_library(X ALIAS Y)`, `::` namespacing, `add_custom_command` from alias | ✓ done                                                                                                                                                   |
| `ObjectLibrary`              | 81    | `OBJECT` library + `$<TARGET_OBJECTS:...>`                                  | ✓ done — new nodes: `Yc_add_custom_command_target`, `Yc_add_definitions`; Transitive subdir dropped (cmake 3.28 vs 4.3 OBJECT INTERFACE dep propagation) |
| `CompileDefinitions`         | ~80   | per-config compile definitions                                              | ✓ done (subdir cmake embedded verbatim)                                                                                                                  |
| `Visibility`                 | 64    | `C_VISIBILITY_PRESET`, `VISIBILITY_INLINES_HIDDEN`                          | ✓ done — POST_BUILD `cmake -P verify.cmake` (nm check); build exit code is oracle                                                                        |
| `LinkStatic`                 | 30    | static lib + `LINK_SEARCH_*` properties                                     | ✓ done                                                                                                                                                   |
| `PositionIndependentTargets` | 14    | `POSITION_INDEPENDENT_CODE` property                                        | ✓ done (3 subdirs, INTERFACE/OBJECT libs)                                                                                                                |

#### Group 3 — Subdirectory tests, all done (multi-file, C/CXX)

| Directory    | Lines (root) | Note                                                      | Status |
| ------------ | ------------ | --------------------------------------------------------- | ------ |
| `TargetName` | 5            | two subdirs: executables + scripts                        | ✓ done |
| `CxxOnly`    | 14           | MODULE lib, dot-in-target-name, mixed `.C`/`.cxx` sources | ✓ done |

#### Group 5 — Large / complex, all done (C/CXX)

All commands covered by the typed yelu API. No `yc_quote_cmd` needed.

| Directory             | Lines | Primary feature                       | Status / note                                                                                                                                                                                                                                                     |
| --------------------- | ----- | ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CompileOptions`      | 108   | compile options + policy guards       | ✓ done — new nodes: `Yc_enable_language`, `Yc_set_source_property`, `append` on `Yc_set_property`; `cmake_quote_cond` fix for `()`                                                                                                                                |
| `CompileFeatures`     | 445   | `target_compile_features` + standards | ✓ covered by `Tests/CMakeCommands/target_compile_features/`; `Tests/CompileFeatures/` is cmake's compiler-DB validation (`try_compile` intensive) — out of scope                                                                                                  |
| `GeneratorExpression` | 504   | comprehensive genex testing           | ⊘ skipped — cmake's own genex regression suite; `file(GENERATE)` missing; see `doc/cmake/genex.md`                                                                                                                                                               |
| `CustomCommand`       | 609   | `add_custom_command` full coverage    | ✓ done — yelu-only (`check_build_yelu`); upstream uses generator-exe subdirs, shell operators, genex, `COMMAND_EXPAND_LISTS` — not tractable as reference. New fields: `verbatim`/`comment` on `Yc_add_custom_command`, `all`/`depends` on `Yc_add_custom_target` |

#### Group 6 — Blocked / tractable

| Directory        | Blocker                                                                                      |
| ---------------- | -------------------------------------------------------------------------------------------- |
| `PolicyScope`    | `cmake_policy(PUSH/POP/SET)` — Y11 design blocked                                            |
| `StringFileTest` | `string(REGEX QUOTE)` — now available (4.3); needs `Sc_regex_quote` in AST + PP + yelu layer |
| `TryCompile`     | `try_compile` needs compiler at configure time                                               |

#### Groups 7–11 — Out of scope

| Group    | Description                                                         |
| -------- | ------------------------------------------------------------------- |
| Group 7  | cmake infrastructure (CTest/CPack/ExternalProject) — different domain |
| Group 8  | Language-specific (`Fortran*`, `CUDA*`, `CSharp*`, `Swift*`, etc.) |
| Group 9  | Find* modules (~70 dirs) — need corresponding packages installed    |
| Group 10 | Platform / generator specific (`VS*`, `CFBundle*`, `XCTest`, etc.) |
| Group 11 | Trivial / no assertions (`VariableUsage`, `EmptyDepends`, `EmptyProperty`) |

---

### RunCMake Tests — Per Directory

`Tests/RunCMake/<command>/` — one directory per command, each `.cmake` script uses
`project(${RunCMake_TEST} NONE)`. Of 431 total: ~80 `CMP*` policy dirs, ~100+ toolchain/platform dirs, ~100+ cmake-infra dirs. Tractable subset: ~30 scripting-only command dirs. Ceiling: ~67 scripts from ~15 dirs.

#### Done dirs (64 compat + 50 pairs)

| Dir                            | Compat scripts                                                                                                                                                                                                                         | Yelu pairs                       | Notes                                                                                |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------ |
| `variable_watch`               | ModifiedAccess, ModifyWatchInCallback, NoWatcher, RaiseInParentScope, WatchTwice                                                                                                                                                       | all 5                            | ✓                                                                                    |
| `cmake_path`                   | ABSOLUTE_PATH, APPEND, APPEND_STRING, COMPARE, CONVERT, GET, HASH, HAS_ITEM, IS_ABSOLUTE, IS_PREFIX, IS_RELATIVE, NATIVE_PATH, NORMAL_PATH, RELATIVE_PATH, REMOVE_EXTENSION, REMOVE_FILENAME, REPLACE_EXTENSION, REPLACE_FILENAME, SET | all 19 (exit-0 only, no stdout)  | ✓                                                                                    |
| `while`                        | CMP0130-OLD, CMP0130-WARN, CMP0130-common, EndMismatch                                                                                                                                                                                 | counter + break                  | ✓; OLD/-WARN use `check_from_dir`                                                    |
| `return`                       | CMP0140-NEW, CMP0140-OLD, PropagateNothing                                                                                                                                                                                             | early + propagate                | ✓; PropagateFromFunction/Directory blocked                                           |
| `option`                       | CMP0077-NEW, CMP0077-OLD, CMP0077-SECOND-PASS, CMP0077-WARN                                                                                                                                                                            | default + respects_var           | ✓                                                                                    |
| `set`                          | Env, ExtraEnvValue, ParentPulling, ParentPullingRecursive                                                                                                                                                                              | ParentPulling + env inline       | ✓                                                                                    |
| `include`                      | EmptyString, EmptyStringOptional, CMP0146-OLD/-WARN, CMP0148-Interp-OLD/-WARN, CMP0148-Libs-OLD/-WARN                                                                                                                                  | EmptyString, EmptyStringOptional | ✓; pairs use `check_pair_text_stderr`; CMP0146/0148 blocked (policy+module)          |
| `math`                         | MATH, Overflow                                                                                                                                                                                                                         | ops + Overflow                   | ✓                                                                                    |
| `list`                         | JOIN, SORT, POP_BACK, POP_FRONT, PREPEND                                                                                                                                                                                               | all 5                            | ✓                                                                                    |
| `string`                       | Concat, Append, Join, Hex, Uuid, Repeat                                                                                                                                                                                                | all 6                            | ✓                                                                                    |
| `foreach`                      | foreach-all-test                                                                                                                                                                                                                       | range + in                       | ✓; upstream ITEMS-before-LISTS → pairs use inline cmake                              |
| `message`                      | newline, message-indent                                                                                                                                                                                                                | newline + indent                 | ✓                                                                                    |
| `get_filename_component`       | KnownComponents (exit-0)                                                                                                                                                                                                               | —                                | ✓ compat; yelu pair todo                                                             |

#### Blocked / open dirs

| Dir                            | Notes                                                                                        |
| ------------------------------ | -------------------------------------------------------------------------------------------- |
| `function`                     | `CMAKE_CURRENT_FUNCTION` uses `list(SUBLIST)`; runtime is 4.3 — re-check if tractable        |
| `include_guard`                | All scripts use `add_subdirectory` — out of scope for `-P` script tests                      |
| `include/ParentVariableScript` | `CMAKE_PARENT_LIST_FILE` chain — needs multi-file fixture infra                              |
| `include` CMP0146/CMP0148      | Deprecated Find module behavior under policy; blocked                                        |
| `foreach-all-test` pair        | PP emits LISTS-first; upstream uses ITEMS-before-LISTS — extend PP or use inline cmake       |

#### Not tractable as RunCMake benchmarks

These commands are implemented in yelu but their RunCMake scripts cannot serve as automated equivalence benchmarks.

| RunCMake test                       | Yelu impl     | Why not a benchmark                                                            |
| ----------------------------------- | ------------- | ------------------------------------------------------------------------------ |
| `try_run`                           | ✓             | run-result is a binary exit code — machine-dependent                           |
| `execute_process`                   | ✓             | output is process-dependent                                                    |
| `file` (DOWNLOAD, GET_RUNTIME_DEPS) | ✓             | network / filesystem runtime                                                   |
| `file` (STRINGS, READ, WRITE, etc.) | ✓             | assertions depend on file contents, not cmake semantics                        |
| `CompileFeatures`                   | ✓             | queries compiler feature database                                              |
| `list/SUBLIST`, `string/JSON/UUID`  | ✓ (own tests) | own tests cover them; RunCMake scripts redundant                               |
| `string/UTF-*`                      | —             | require cmake test fixture files, not standalone scripts                       |
| `CMP*` dirs                         | —             | policy/compat tests, error-case only — always blocked                          |
| `string/RegexEmptyMatch`            | compat ✓      | compat added (CMP0186 NEW default in 4.1+); yelu pair needs Y11 (cmake_policy) |
| `string/RegexClear`                 | —             | uses `add_subdirectory` — configure-mode only                                  |

#### Gotchas

**`include(relative.cmake)` resolution in script mode**: `include(filename.cmake)` (without
`${CMAKE_CURRENT_LIST_DIR}/`) resolves relative to the process CWD, not the script's directory.
CTest sets CWD to the script dir automatically; plain `cmake -P` does not. Fix: `check_from_dir`
in `test_runcmake_compat.ml` prefixes the command with `cd <script-dir> &&`. Applies to any
script that uses bare `include(relative.cmake)` without `${CMAKE_CURRENT_LIST_DIR}/`.

**`{`/`}` in stdout patterns** (e.g. `ENV{VAR}`) cause `Re.Pcre` parse errors — `escape_braces`
in `cmake_runner.ml` escapes them before regex compilation.

---

### Script Test Exclusions

This section tracks every case explicitly dropped or narrowed in the conf-run test suite
(`yelu/test/test-runcmake/`). "✓" in the coverage table means the happy path passes — not
that every cmake edge case is exercised.

#### Undefined / implementation-defined

| Test file         | Case dropped                                             | Reason                                                                                                   |
| ----------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `test_string2.ml` | `STRING(REPLACE "" …)` — empty literal match-string      | No positive RunCMake test exists; cmake docs do not specify it                                           |
| `test_while.ml`   | RunCMake/while positive tests (all CMP0130 policy tests) | Validate policy stack behavior, not loop semantics — not a useful yelu target                            |
| `test_list3.ml`   | `SORT COMPARE NUMBER/NUMERIC`                            | **False feature** — fixed: `Ls_numeric` removed from `lang_cmake.ml`. cmake `list(SORT)` only supports `COMPARE STRING`, `FILE_BASENAME`, `NATURAL`. |

#### Defined behavior — not yet tested

| Test file         | Case not tested                                                          | What's needed                                                                                      |
| ----------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `test_math.ml`    | Integer overflow / underflow                                             | ✓ covered in `overflow` test case (64-bit signed wrap). cmake emits `CMake Warning (dev)` in configure mode but not in `-P` mode — warning not checked. |
| `test_string2.ml` | `REGEX REPLACE` with zero-length match (`^`, `a*`, etc.)                 | Needs CMP0186 policy set — blocked until Y11                                                               |

#### Yelu feature gap

| Test file                    | Case dropped                                            | Missing feature                                       | Notes                             |
| ---------------------------- | ------------------------------------------------------- | ----------------------------------------------------- | --------------------------------- |
| `test_foreach2.ml`           | `ZIP_LISTS` CMP0124 loop-variable scoping               | `cmake_policy(SET CMP0124 NEW)`                       | Y11                               |
| `test_foreach.ml`            | CMP0124 loop variable scoping (NEW vs OLD)              | `cmake_policy`                                        | Y11                               |
| `test_return.ml`             | `return(PROPAGATE …)`                                   | CMP0140 NEW required                                  | Y11                               |
| `test_return.ml`             | `return()` inside `block()` / `add_subdirectory()` scope | subdirectory scope not in yelu                       | —                                 |
| `test_separate_arguments.ml` | `WINDOWS_COMMAND`, `PROGRAM`/`PROGRAM_ARGS`             | Platform-specific — would need Windows CI             | Skip                              |
| `test_message2.ml`           | `CMAKE_MESSAGE_CONTEXT` nested push/pop via functions   | Low value for scripting-only tests                    | Skip                              |
| `test_function.ml`           | `CMAKE_CURRENT_FUNCTION_LINE`                           | Not populated in cmake `-P` script mode               | Revisit if configure-mode tests added |
| `test_string_uuid.ml`        | `string(UUID …)` GET_RAW, STRING_ENCODE                 | Available on cmake 4.3; not yet in yelu AST            | —                                 |
| —                            | `string` UTF-16/32 encoding                             | Absent from cmake AST; niche                          | Skip                              |
| —                            | `include_guard` DIRECTORY/GLOBAL conf-run               | Requires `include()` + multiple files                 | Out of scope for `-P` tests       |
| `test_configure.ml`          | `try_compile` old project form (`<bindir> <srcdir>`)    | Legacy interface; not in yelu API by design           | 20 RunCMake old-form tests skipped |
| `test_configure.ml`          | `try_compile` CMP policy variants                       | `cmake_policy` not in yelu                            | Y11                               |
| `test_configure.ml`          | `try_compile` CUDA / ISPC                               | Exotic compilers not available                        | Skip                              |
| `test_configure.ml`          | `try_compile` ConfigureLog / ProjectVars / TopIncludes  | cmake internals not exposed in yelu                   | Ignore                            |
| `test_configure.ml`          | `try_run` configure+run tests                           | Run result is machine-dependent binary exit code      | Compile half tested via `try_compile` |

#### Partial coverage

| Test file                                      | What is tested                                                                                                                              | What is not tested                                                                              | Priority |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | -------- |
| `test_string*.ml` (×4)                         | APPEND, JOIN, CONCAT, REPEAT, FIND, SUBSTRING, STRIP, REPLACE, REGEX REPLACE/MATCH/MATCHALL, TOUPPER, TOLOWER, LENGTH, PREPEND, COMPARE, HEX | Bracket-string args; REGEX REPLACE multiple capture groups; TIMESTAMP (time-dependent); UTF-8  | Low      |
| `test_math.ml`                                 | All operators; DECIMAL/HEX output; overflow wrap                                                                                            | Operator precedence edge cases                                                                  | Low      |
| `test_list*.ml` (×4)                           | All 17 subcommands; TRANSFORM (7 actions × 3 selectors)                                                                                     | SORT full option matrix; TRANSFORM GENEX_STRIP; TRANSFORM FOR with step                         | Low      |
| `test_set.ml`                                  | Normal set/unset; PARENT_SCOPE; CACHE first-write-wins; PATH/BOOL/STRING types; unset(CACHE)                                                | CACHE FILEPATH/INTERNAL; recursive PARENT_SCOPE; type coercion                                  | Low      |
| `test_if.ml`                                   | IN_LIST, MATCHES, VERSION_*; AND/OR; numeric/string comparisons; EXISTS/IS_DIRECTORY                                                        | IS_NEWER_THAN, IS_SYMLINK; file permission tests                                                | Low      |
| `test_separate_arguments.ml`                   | UNIX_COMMAND (simple/quoted/empty); NATIVE_COMMAND (simple)                                                                                 | Complex shell quoting                                                                           | Low      |
| `test_set_env.ml`                              | Read pre-set env var; set/unset ENV{}                                                                                                       | Undefined env var; env var with `=` in value                                                    | Low      |
| `test_message*.ml`                             | All 14 modes + CONTEXT/INDENT                                                                                                               | Nested CONTEXT push/pop via functions                                                           | Low      |
| `test_configure.ml` (try_compile)              | pass/fail source; OUTPUT_VARIABLE; C/CXX_STANDARD (6 configure tests)                                                                      | LINK_OPTIONS/COPY_FILE (in AST, not conf-run tested)                                            | Low      |

---

### Tutorial V2 (CMake 4.3) — Done

V1 (CMake 3.20, `src/bin/cmake/v1/`): 12 steps, single "Tutorial" project, C++11, no FILE_SET.

V2 (CMake 4.3, `src/bin/cmake/v2/`): two top-level projects (`TutorialProject` + `SimpleTest`),
11 `CMakeLists.txt` files, C++20, `FILE_SET HEADERS`, `GNUInstallDirs`, `CheckIPOSupported`,
`CheckIncludeFiles`, `CheckSourceCompiles`, `find_package` (SimpleTest / TransitiveDep).

**Status**: 11/11 — `make cmake-check-v2` and `make yelu-check-v2` both 11/11 ✓.
Reference: `vendor/cmake/Help/guide/tutorial/Complete/`.

New AST added: `Bracket of string` arg type; `namespace` on `Install_export`;
`arch_independent` on `Yc_write_basic_package_version_file`; `find_package`,
`cmake_minimum_required`, `add_library_alias` utils; `Yc_apply` for
`check_include_files`, `check_source_compiles`, `check_ipo_supported`,
`install(FILE_SET)`, `find_path PATH_SUFFIXES`, `simpletest_discover_tests`.

---

### Test Infrastructure

#### CMakeOnly test harness

Each CMakeOnly test has a yelu equivalent under `test/test-cmake-only/`:

```
test/test-cmake-only/
  find_library/
    ref/CMakeLists.txt   ← copy from Tests/CMakeOnly/find_library/
    yelu.ml              ← yelu program producing equivalent cmake
  find_path/
    ...
```

Validation: `make file-api-test` compares `Tests/CMakeOnly/<test>/CMakeLists.txt`
(reference) against yelu-generated cmake via File API comparison.
