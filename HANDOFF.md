# Handoff — 2026-06-07

## What we did

**fmT probe migration** — converting `.ml` → `.yc` for the fmt project probe.
7 of 11 helpers are `.yc` files. The remaining 4 `.ml` files have ~67 `yc_apply`
calls that are fully diagnosed.

**10 typed-API gaps closed**. Every cmake builtin used by fmt now has a proper
yc API: `message` modes, `export ~file`, `find` kwargs, `execute_process`,
`add_custom_command`, `set_target_properties`, `add_custom_target`,
`set_source_files_properties`, `install_files`/`install_targets`.

**4-tier IR fidelity model**: typed IR → `cmake_lang` → `yc_raw` → `yc_apply`.
Documented in [`ir_tiers.md`](doc/yelu_cmake/ir_tiers.md).

**Parser infrastructure**: `split_by_keywords` splits positional args by keyword
markers (used by `add_custom_command`, `execute_process`, `set_property`,
`set_target_properties`). `args_to_cmake_text` helper for `yc_raw` fallback.

**Wellform**: `Yc_primitives` (90 command names), `Yc_wellform` (3 checks:
reserved names, apply shadowing, raw tainted). Wired into `Yc_driver`.
CLI warns on violations, doesn't block compilation.

**`ECmakeRaw`**: moved from fragment to core `Yelu_cmake.expr`. Single
verbatim-text escape hatch. Parser: `yc_raw <expr>`.

**String-as-enum plan**: `visibility`, `mode`, `compatibility`, `cache_type`
should be variants, not strings. Documented in `ir_tiers.md`.

## Remaining work

### Probes/fmt — 67 `yc_apply` calls remaining

| Category | Count | What |
|---|---|---|
| Project functions | 23 | Legitimate — cmake functions from original fmt |
| Restructuring | 22 | Raw→typed arg conversion (export, install, configure_file, etc.) |
| Dynamic visibility | 7 | `EVar "kind"` in target_* — needs visibility variant |
| Other design gaps | 15 | set_property SOURCE, cmake_parse_arguments, string/file subcommands |

### Design-level TODOs

1. **Visibility variant** — `type visibility = Public | Private | Interface`.
   Replace `string` in all 7 target commands. Dynamic `${kind}` falls to `yc_raw`.

2. **Recursive parse↔meta-eval loop** — for `${kind}` resolution at configure-time.
   `yc_raw` is the placeholder.

3. **Cross-module enums** — `supported_lang_of_string`, `compatibility_of_string`
   for `yc_project`, `yc_write_basic_package_version_file`.

4. **`cmake_parse_arguments`** — no typed API. cmake builtin for parsing function
   kwargs. Used by `add_fmt_test`, `expect_compile`.

### Remaining .ml files in probes/fmt

| File | yc_apply count | Primary blockers |
|---|---|---|
| `main.ml` | 42 | Project functions + restructuring (export, install, configure_file) |
| `test_main.ml` | 11 | Project functions + add_test with list concat + cmake_parse_arguments |
| `cuda_test.ml` | 3 | set_property SOURCE APPEND, cuda_add_executable (project func) |
| `compile_error_test.ml` | 13 | expect_compile/run_tests (project funcs), file/list/string subcommands |

## Key files changed

- `src/langs/yelu/yelu_parse.ml` — `split_by_keywords`, `args_to_cmake_text`, `yc_raw` fallback, family dispatch aliases, target/install/property handler fixes
- `src/langs/yelu/yc_primitives.ml` — 90 command names
- `src/langs/yelu/yc_wellform.ml` — 3 check functions
- `src/langs/drivers/yc_driver.ml` — wellform wired in
- `src/langs/yelu/yelu_cmake.ml` — `ECmakeRaw` in core type
- `probes/fmt/*.yc` — 7 converted files
- `probes/fmt/*.ml` — cleaned up yc_apply escapes
- `doc/yelu_cmake/ir_tiers.md` — new doc
- `doc/cmake/painpoints.md` — §9 (metaprogramming) + §10 (string-as-enum)

## Session state (2026-06-07)

### Test baseline
```
dune test → 291 OK, 6 FAIL (3 pre-existing × 2)
  - include optional (PP trailing space)
  - snapshot loads with comments
  - ylet chain (variable resolution)
```

### Extension scheme
| Extension | Language | Status |
|---|---|---|
| `.yc` | yelu_cmake (cmake-faithful) | Production |
| `.ycn` | yelu_cmake_normal | Research (parser/printer stubs) |
| `.ye` | Reserved for future non-cmake packs | — |

### Probes/fmt converted (.yc)
```
probes/fmt/join_paths.yc
probes/fmt/find_setenv.yc
probes/fmt/gtest.yc
probes/fmt/add_subdirectory_test.yc
probes/fmt/find_package_test.yc
probes/fmt/static_export_test.yc
probes/fmt/fuzzing.yc
```

### Probes/fmt remaining (.ml)
```
probes/fmt/main.ml           — 42 yc_apply (project funcs + restructuring)
probes/fmt/test_main.ml       — 11 yc_apply (project funcs + add_test concat)
probes/fmt/cuda_test.ml       —  3 yc_apply (set_property SOURCE)
probes/fmt/compile_error_test.ml — 13 yc_apply (expect_compile/run_tests funcs)
```

### Original cmake reference
```
/home/red/code/contrib/fmt-all/fmt/
  CMakeLists.txt              → main.ml
  test/CMakeLists.txt         → test_main.ml
  test/cuda-test/CMakeLists.txt → cuda_test.ml
  test/compile-error-test/CMakeLists.txt → compile_error_test.ml
  support/cmake/JoinPaths.cmake → join_paths.yc
  support/cmake/FindSetEnv.cmake → find_setenv.yc
```

Original fmt defines cmake functions: `join`, `set_verbose`, `setup_target`,
`add_module_library`, `add_doc_target` (root), `add_fmt_test` (test/),
`expect_compile`, `run_tests` (compile-error-test/), `join_paths` (JoinPaths.cmake).

### Fresh docs to review
- [`doc/yelu_cmake/ir_tiers.md`](doc/yelu_cmake/ir_tiers.md) — 4-tier IR fidelity
- [`doc/yelu_cmake/driver.md`](doc/yelu_cmake/driver.md) — pipelines + tool interface
- [`doc/cmake/painpoints.md`](doc/cmake/painpoints.md) — updated §9-10
- [`doc/yelu_cmake/status.md`](doc/yelu_cmake/status.md) — parser coverage summary

### Fresh code to review
- [`src/langs/yelu/yc_primitives.ml`](src/langs/yelu/yc_primitives.ml) — 90 commands
- [`src/langs/yelu/yc_wellform.ml`](src/langs/yelu/yc_wellform.ml) — wellform checks
- [`src/langs/yelu/yelu_parse.ml`](src/langs/yelu/yelu_parse.ml) — `split_by_keywords` (~L285), `args_to_cmake_text` (~L296), target family `_ ->` fallback (~L805), cmake-name aliases (~L732-738)
- [`src/langs/drivers/yc_driver.ml`](src/langs/drivers/yc_driver.ml) — wellform wired in (~L49)
- [`src/langs/yelu/yelu_cmake.ml`](src/langs/yelu/yelu_cmake.ml) — `ECmakeRaw` in core type (~L847)
- [`probes/fmt/fuzzing.yc`](probes/fmt/fuzzing.yc) — example of a converted .yc with function definition

### Tool directories
```
src/langs/drivers/           — per-language driver modules + cross-lang utils
tool/cmake_text/              — cmake text tools (parse, reprint, scan, index, oracle)
```

## Quick start

```sh
dune build                    # build everything
dune test                     # 291 OK, 6 FAIL (3 pre-existing × 2)
dune exec src/bin/yelu/yelu.exe -- compile probes/fmt/fuzzing.yc  # test a .yc
```
