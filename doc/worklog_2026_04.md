# Yelu Worklog — April 2026

Implementation history. For current state see `yelu_lang_coverage.md`.

---

## Tier 1 — find_* + message + math + CMakeOnly (done 2026-04-13)

**Goal**: expand find_* stubs; add message (14 modes) and math; unblock TargetScope and
LinkInterfaceLoop CMakeOnly tests.

| Item                          | What was done                                                                                                                          |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `find_library`                | `find_var_args` record, PP, utils, `Yc_find_library`, compile                                                                          |
| `find_path`                   | same shape                                                                                                                             |
| `find_program`                | same shape                                                                                                                             |
| `find_file`                   | same shape                                                                                                                             |
| `message`                     | 14-variant `message_mode`, `Mm_none`…`Mm_deprecation`; utils fn                                                                        |
| `math`                        | `math` utils fn wrapping `Math_lib`                                                                                                    |
| `TargetScope` test (×4 files) | `add_library_imported`, `Plain` target_kind, `Lang_none` — cmake-only-check OK                                                         |
| `LinkInterfaceLoop` test      | imported shared libs + circular dep via set_target_properties — cmake-only-check OK                                                    |
| `find_path` CMakeOnly test    | macro, unset_cache, ARGN splat, file(RELATIVE_PATH), if/elseif, STREQUAL — cmake-only-check OK                                         |
| `find_library` CMakeOnly test | + get_filename_component, string(REGEX REPLACE), set_property GLOBAL, foreach — cmake-only-check OK                                    |
| New features (unlocked)       | `Yc_macro`, `Yc_unset_cache`, `Yc_file_relative_path`, `Ystrequal`, `elseif` PP, `Yc_set_global_property`, `Yc_get_filename_component` |

---

## Tier 2 — list/string/foreach/while + SelectLibraryConfigurations (done 2026-04-17)

**Goal**: cover remaining pure-scripting language features.

| Item                                                   | What was done                                                                                 |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| `foreach` (all 4 forms incl. ZIP_LISTS)                | `commands` body field; utils + yelu AST + compile + 6 yelu tests                              |
| `list` (17/17 sub-commands incl. TRANSFORM)            | `List_cmd of list_cmd`; full utils + yelu AST + compile + conf-run tests                      |
| `string` (19/19 cmake-AST subcommands + JSON/UUID/HEX) | `String_cmd of string_cmd`; HEX added; full pipeline + conf-run tests                         |
| `while` / `break` / `continue` / `return`              | utils + yelu AST + compile + 5 yelu tests                                                     |
| `SelectLibraryConfigurations` CMakeOnly showcase       | `get_property GLOBAL`, macro, double-expansion `${${basename}_LIBRARY}` — cmake-only-check OK |
| `MajorVersionSelection` CMakeOnly showcase             | concrete OpenSSL/3 instantiation; `cmake -S -B` passes                                        |

Blocked in Tier 2:
- `CheckSymbolExists` — requires C compiler at runtime
- `CheckCXXCompilerFlag` — requires CXX compiler + `execute_process`

---

## Tier 3 — find_package + file() + execute_process + showcases (done 2026-04-18)

**Goal**: make yelu usable for real projects with external dependencies and filesystem ops.

| Item                             | What was done                                                                                                                                        |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `find_package` (basic + CONFIG)  | version/EXACT/QUIET/REQUIRED/COMPONENTS/OPTIONAL_COMPONENTS/CONFIG — 8 unit tests                                                                    |
| `file(GLOB/GLOB_RECURSE)`        | full pipeline; `configure_depends`, `relative` options; 4 unit tests                                                                                 |
| `file()` IO subcommands          | READ, WRITE, APPEND, STRINGS — full pipeline; 6 unit tests                                                                                           |
| `file()` filesystem subcommands  | TOUCH/TOUCH_NOCREATE, MAKE_DIRECTORY, RENAME, REMOVE/REMOVE_RECURSE, COPY_FILE — 8 unit tests                                                        |
| `file()` path-query subcommands  | REAL_PATH, SIZE, READ_SYMLINK, TIMESTAMP — 4 unit tests                                                                                              |
| `execute_process`                | multi-COMMAND, output/error/result capture, all flags (WORKING_DIRECTORY, TIMEOUT, OUTPUT_QUIET, ERROR_QUIET, COMMAND_ERROR_IS_FATAL) — 6 unit tests |
| `MajorVersionSelection` showcase | `major_version_selection.ml`; `cmake -S -B` passes                                                                                                   |
| `FetchContent` showcase          | `fetch_content.ml` — `include(FetchContent)` + Declare/MakeAvailable via `yc_apply`; `cmake -S -B` passes                                            |
| `AllFindModules` showcase        | `all_find_modules.ml` — real `file(GLOB)` enumeration + macro loop; `cmake -S -B` passes                                                             |
| Compiler warning fix             | `warn_undeclared_cvar` suppressed for names containing `${` (dynamic macro refs)                                                                     |

---

## Tier 4 — Generator expressions (done 2026-04-18)

**Goal**: typed `$<…>` constructors as a surface API; raw strings remain valid as fallback.

New type `yelu_genex` in `lang_yelu.ml` with `genex_to_string` + `yge : yelu_genex → yarg`
in `lang_yelu_utils.ml`. No changes to compile pipeline — genex folds into `Ycs_val` path
and gets auto-quoted by the compiler due to the `$<` prefix check.

| Constructor                                     | Emits                                             |
| ----------------------------------------------- | ------------------------------------------------- |
| `Yge_config`                                    | `$<CONFIG:cfg>`                                   |
| `Yge_not/and/or`                                | `$<NOT:…>` / `$<AND:…>` / `$<OR:…>`               |
| `Yge_if`                                        | `$<IF:cond,t,f>`                                  |
| `Yge_bool`                                      | `$<BOOL:s>`                                       |
| `Yge_target_file`                               | `$<TARGET_FILE:tgt>`                              |
| `Yge_target_file_dir`                           | `$<TARGET_FILE_DIR:tgt>`                          |
| `Yge_target_property`                           | `$<TARGET_PROPERTY:tgt,prop>`                     |
| `Yge_install_interface` / `Yge_build_interface` | `$<INSTALL_INTERFACE:…>` / `$<BUILD_INTERFACE:…>` |
| `Yge_strequal`                                  | `$<STREQUAL:a,b>`                                 |
| `Yge_lower_case` / `Yge_upper_case`             | `$<LOWER_CASE:…>` / `$<UPPER_CASE:…>`             |
| `Yge_compile_language`                          | `$<COMPILE_LANGUAGE:lang>`                        |
| `Yge_platform_id`                               | `$<PLATFORM_ID:id>`                               |
| `Yge_raw`                                       | escape hatch — user supplies full inner content   |

13 unit tests. No showcase uses typed genex yet (existing code uses `ystr_raw "$<…>"`).

---

## cmake_language + block() + cmake_path (done 2026-04-18)

**Goal**: cover metaprogramming, scope isolation, and path manipulation commands.

| Item                           | What was done                                                                                                       |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `cmake_language(CALL …)`       | `Yc_cmake_language_call`; converts yarg to `exp` via `arg_to_exp` helper; 2 unit tests                             |
| `cmake_language(EVAL CODE …)`  | `Yc_cmake_language_eval`; auto-adds quotes around code string in compile step; 1 unit test                          |
| `cmake_language(GET_MESSAGE…)` | `Yc_cmake_language_get_log_level`; 1 unit test                                                                      |
| `block()` / `endblock()`       | Added `body : cmd list` field to `block_exp` in cmake AST (was missing); PP prints body between delimiters; `Yc_block` with scope_vars/propagate/body; 4 unit tests |
| `cmake_path`                   | New `cmake_path_cmd` sum type in cmake AST with 20 constructors; `pp_cmake_path` in PP; full yelu AST + compile + utils; 30 unit tests covering all subcommands |

Total: 173 unit tests. `block_exp.body` fix was a real AST gap (PP was emitting empty block bodies).

---

## RunCMake compat + yelu pairs expansion — Y1 + Tier 3 (done 2026-04-19)

**Goal**: wire RunCMake tests into dune, add yelu pairs across all tractable script-mode dirs,
complete CMakeOnly showcase coverage, add stderr alignment checking.

### Y1 — File API test alias

`cmake_file_api_cmp.py` now runs under `dune test` via `dune build @yelu/test/test-file-api/file-api-test`.
Key fixes:
- `(glob_files ../../src/bin/yelu/*.exe)` + `(promote (until-clean))` — dune sandbox isolation
  (sandbox only exposes declared deps; promoted exes are in the source tree, visible as glob deps)
- `(setenv TOLA %{workspace_root})` — gives the Python script a stable root path
- `run_file_api.py` uses source-tree promoted exes (not `_build/` path)
All 12 step pairs pass File API comparison.

### ProjectInclude* CMakeOnly showcases

2 new yelu programs (`project_include.ml`, `project_include_before.ml`) cover all 4 suites
(ProjectInclude, ProjectIncludeAny, ProjectIncludeBefore, ProjectIncludeBeforeAny).
Any/non-Any variants share CMakeLists content — only the cmake configure flags differ.
CMakeOnly showcase count: 8/12 → 12/12. All pass `make cmake-only-check`.

### RunCMake compat — include (8 tests)

Added `include` group: EmptyString, EmptyStringOptional, CMP0146-OLD/-WARN, CMP0148-Interp-OLD/-WARN, CMP0148-Libs-OLD/-WARN.
EmptyString/Optional upgraded to also assert the key warning appears in stderr (`check_stderr_matches`).

### RunCMake yelu pairs — math/list/string/foreach/message + cmake_path (36 → 48)

Added 12 new pairs across 5 compat dirs:

| Dir       | Pairs added                                 |
| --------- | ------------------------------------------- |
| `math`    | ops (OUTPUT_FORMAT inline), Overflow        |
| `list`    | JOIN, SORT, POP_BACK, POP_FRONT, PREPEND    |
| `string`  | Concat, Append, Join, Hex, Uuid, Repeat     |
| `foreach` | range (inline), in (inline)                 |
| `message` | newline (inline), indent                    |

cmake_path pairs: 6 → 18 (added SET, ABSOLUTE_PATH, APPEND_STRING, IS_RELATIVE, IS_PREFIX, HAS_ITEM, HASH, RELATIVE_PATH, REMOVE_EXTENSION, REPLACE_FILENAME, CONVERT, NATIVE_PATH).

### stderr alignment checking (50th pair — include EmptyString/Optional)

New infrastructure in `cmake_runner.ml`:
- `normalize_cmake_filepath s` — replaces any `*.cmake` path with `<cmake>` for comparison
- `check_stderr_normalized ref yelu text` — compares normalized stderr between two runs

New test helper `check_pair_text_stderr` in `test_runcmake_yelu.ml` — like `check_pair_text` but
also checks stderr equality after filepath normalization. Used for negative-path tests that produce
warnings with no stdout (EmptyString, EmptyStringOptional).

Key insight: the `-stderr.txt` pattern files from RunCMake assume a CMakeLists.txt call stack
(the CTest framework runs scripts via `include()` from a parent). Running in `-P` mode directly
has no parent, so the call stack differs. Fix: compare normalized stderr between two `-P` mode
runs (ref inline cmake vs yelu cmake) rather than matching against the upstream pattern files.

Total pairs: 50. Compat tests: 62.

---

## TODO completions (2026-04-21)

**Y1** — File API wired into tests: `make file-api-test` runs cmake configure + codemodel-v2
diff for all 12 steps (yelu-generated vs reference cmake).

**Y9** — RunCMake positive-test gap audit complete. Gaps are real (cmake 4.3 still
has no positive RunCMake scripts for `list` FIND/REMOVE_ITEM/REMOVE_AT/REVERSE/LENGTH/GET
or `string` FIND/SUBSTRING/STRIP/REPLACE/LENGTH; `Tests/StringFileTest/` fills some
regex cases but not these). No impact on yelu — standalone tests in `test_list*.ml`
and `test_string*.ml` cover all these subcommands independently.

**Y10** — `string(JSON …)` and `string(UUID …)` fully implemented:
`Sc_uuid`/`Sc_json`/`json_op` in `lang_cmake.ml`; PP; `yelu_json_op` + yelu layer;
8 UUID tests + 8 JSON tests all pass. `GET_RAW`/`STRING_ENCODE` are cmake 4.3+ (we're
on 3.28); `Jop_get_raw`/`Jop_string_encode` exist in AST but not tested.
Key fix: `Ycs_cmake` compiles to `Bare` (not `Quoted`) so bracket strings pass through.
