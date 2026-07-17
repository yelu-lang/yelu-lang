# fmt — predictor probe

> **Project**: [{fmt}](https://github.com/fmtlib/fmt) C++ formatting library
> **Vendored at**: `vendor/fmt` → `/home/red/code/contrib/fmt-all/fmt`
> **Why this probe**: small CMakeLists (~600 lines) with rich configure-time
> work — `find_program`, `find_package`, `try_compile`, `add_subdirectory`,
> function definitions, 12 user-facing options. Good first probe — broad
> coverage in a compact surface.

## Status (2026-07-16)

> The corpus is labeled-only (Step 2), guarded by the build-time
> `compile-corpus` gate, and the matrix compares **three channels per cell**
> since 2026-07-16 (the tripled oracle — see below).

| oracle | result |
|---|---|
| parse-print roundtrip | 11/11 OK |
| .yc compilation | 11/11 OK (build-time gate in `dune test`) |
| matrix — CMakeCache (24 cells) | 24/24, 0 semantic |
| matrix — file-api codemodel-v2 | 24/24, 29 target/codemodel keys 0-differ |
| matrix — ctest definitions | 24/24 MATCH (full command args) |
| raw cmake escapes | 4 (dynamic visibility ×3 + MSVC flag scan — by design) |

> **Why three channels:** the cache diff is structurally blind to target
> properties, install rules, and test definitions — three real bugs hid there
> (audit 2026-06/07). The codemodel + ctest channels close that class; their
> first run also caught a contaminated `vendor/fmt/CMakeLists.txt` (an old
> yelu emit had overwritten upstream) and a never-ported
> posix-mock-test/os-test block.

**Verdict: functionally complete.** Every cmake file under `vendor/fmt/`
has a `.yc` concrete-syntax equivalent that compiles and produces
byte-identical cmake output (modulo cosmetic whitespace). The matrix
oracle confirms identical `CMakeCache.txt` across all 24 option flips.

## Layout

```
probes/fmt/
├── main.json              ← 4 lines: project, source_dir, out_root
├── main.yc                    ← CMakeLists.txt (297 lines .yc)
├── test/
│   ├── CMakeLists.yc          ← test/CMakeLists.txt
│   ├── fuzzing/CMakeLists.yc
│   ├── gtest/CMakeLists.yc
│   └── ...                    ← (7 more test subdirs)
└── support/cmake/
    ├── join_paths.yc          ← JoinPaths.cmake (snake_case → CamelCase)
    └── find_set_env.yc        ← FindSetEnv.cmake
```

`.yc` files mirror the `vendor/fmt` directory structure. Auto-discovery
maps `*.yc` → target file by naming convention:

```
CMakeLists*.yc  →  CMakeLists.txt        (always)
snake_case.yc   →  CamelCase.cmake       (underscore → module)
anything-else.yc →  CMakeLists.txt       (default)
```

(The legacy `.ml` OCaml-DSL emitters — `main.ml` / `test_main.ml` /
`compile_error_test.ml` — were **retired 2026-06-19**, superseded by the `.yc`
corpus the matrix/manifest actually use. The `.yc` files are now the sole
source.)

## How to run

```sh
# Compile a single .yc file
dune exec src/bin/yelu/yelu.exe -- compile probes/fmt/main.yc

# One hybrid run (compiles all .yc; diffs cache + codemodel + ctest)
dune exec src/bin/yelu/yelu.exe -- hybrid probes/fmt
dune exec src/bin/yelu/yelu.exe -- hybrid probes/fmt -D FMT_FUZZ=ON

# Full matrix (all 24 option cells, each under the tripled oracle)
dune exec src/bin/yelu/yelu.exe -- matrix probes/fmt
```

The hybrid driver:
1. Auto-discovers `.yc` files by walking `probes/fmt/`
2. Compiles each in-process (`parse → emit_ast → cmake pp`)
3. Checks out `vendor/fmt` via `git worktree add --detach`
4. Overwrites the 11 target files with generated cmake
5. Runs `cmake -B` on both vendor and hybrid, diffs stripped caches
6. Reports: `MATCH` / `DIVERGE` with categorized diff (path / non-det / semantic)
7. Saves full log to `_out/fmt/yelu/log/log_<ts>.txt`

## Project spec — user-knob surface

The 12 `option()` declarations in `vendor/fmt/CMakeLists.txt`. Each
is what a downstream user can flip via `-DFMT_X=…`.

| name | default | gates |
|---|---|---|
| `FMT_DOC` | `${FMT_MASTER_PROJECT}` | `add_doc_target()` (find_program doxygen/mkdocs) |
| `FMT_INSTALL` | `${FMT_MASTER_PROJECT}` | all `install()`, `export()`, `configure_package_config_file`, CPack, pkgconfig |
| `FMT_TEST` | `${FMT_MASTER_PROJECT}` | `add_subdirectory(test)` |
| `FMT_FUZZ` | `OFF` | `add_subdirectory(test/fuzzing)` + `FMT_FUZZ` compile def |
| `FMT_CUDA_TEST` | `OFF` | `enable_language(CUDA)` probe (silent on missing toolchain) |
| `FMT_OS` | `ON` | `target_sources(fmt PRIVATE src/os.cc)` vs compile def `FMT_OS=0` |
| `FMT_MODULE` | `${FMT_USE_CMAKE_MODULES}` | `add_module_library()` with `FILE_SET CXX_MODULES` |
| `FMT_SYSTEM_HEADERS` | `OFF` | `SYSTEM` flag on include dirs |
| `FMT_UNICODE` | `ON` | compile def + MSVC `/utf-8` |
| `FMT_PEDANTIC` | `OFF` | GNU/Clang/MSVC pedantic flag blocks |
| `FMT_WERROR` | `OFF` | `-Werror` / `/WX` |
| `FMT_FUZZ_LINKMAIN` | `On` | (inside fuzz subdir; only active when `FMT_FUZZ=ON`) |

Two options (`FMT_OS`, `FMT_PEDANTIC`) have cache-invisible effects
— they change target properties but don't write cache entries.

## Known limitations

- **Windows / MSVC / CUDA branches** are migrated but never exercised
  (matrix runs on Linux). Codegen is verified (cmake parses them without
  error); semantic correctness is untested.
- **Build / test / install oracles** not yet implemented. The matrix only
  proves configure-time equivalence.
- **3 dynamic-visibility raw escapes** remain — `${kind}` in `setup_target`
  can't be a static `Vis_public | Vis_private | Vis_interface`. By design.
- **cmake_parse_arguments** and **FILE_SET CXX_MODULES** still route
  through `yc_apply` — no typed IR yet.

## Related

- [`migration_status.md`](migration_status.md) — full phase log, `yc_apply`
  footprint, known limitations detail
- [`main.json`](main.json) — hybrid driver configuration
- [`../../doc/worklog/worklog_2026_06.md`](../../doc/worklog/worklog_2026_06.md) —
  Phase 8 archival entry
- [`../../doc/yelu_cmake/hybrid_strategy.md`](../../doc/yelu_cmake/hybrid_strategy.md) —
  strategy doc (cmake-as-assembly)
- [`../cache_matrix.md`](../cache_matrix.md) — matrix oracle methodology
