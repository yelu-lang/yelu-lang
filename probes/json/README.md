# json — predictor probe

> **Project**: [nlohmann/json](https://github.com/nlohmann/json) — header-only
> JSON for Modern C++
> **Vendored at**: `vendor/json` → `/home/red/code/contrib/json-all/json`
> **Pin**: tag **v3.12.0**, commit `55f93686c01528224f448c19128836e7df245f72`
> **Why this probe**: the INTERFACE-library canon. A compact 225-line root with
> 11 options, a full Config-package `install()`/`export()` block, genex-driven
> compile definitions, and a dynamic `SYSTEM` include attribute — the shapes fmt
> (a compiled library) never exercised.

## Status (2026-07-29) — first pass complete

| oracle | result |
|---|---|
| `.yc` corpus compile gate (`dune test`) | 1/1 ok |
| matrix — CMakeCache (18 cells) | **18/18** |
| matrix — file-api codemodel-v2 | **18/18**, 128 keys, 0 differ |
| matrix — ctest definitions | **18/18** MATCH (101 tests both sides) |
| generated package files (extra hand check) | `…Config.cmake`, `…ConfigVersion.cmake`, `.pc` byte-identical |
| evaluator-channel smoke | 22 cells, median 11 matched, all cells stable |
| raw cmake escapes | **4** — every one a recorded gap (J1–J4), none stylistic |

**Verdict: complete first pass.** The root `CMakeLists.txt` has a `.yc`
equivalent that parses, wellforms, and emits; the emitted cmake is
configure-equivalent to upstream across all 18 option cells on all three
channels. Five yelu_cmake gaps were found; all are recorded in
[`migration_status.md`](migration_status.md) § Gaps found and **none** was
patched (charter boundary).

## Layout

```
probes/json/
├── main.json              ← driver config: project, source_dir, out_root, 9 matrix options
├── dune                   ← corpus-compile gate (copied verbatim from probes/fmt/dune)
├── main.yc                ← CMakeLists.txt (186 lines .yc ← 225 lines cmake)
├── README.md              ← this file
└── migration_status.md    ← running log + gap registry
```

Scope is **root-only**: `tests/` and `cmake/ci.cmake` are not translated.
`JSON_BuildTests` defaults ON and `tests/` therefore configures — from
*upstream* text on both sides of every cell, which keeps it neutral to the
comparison while making the ctest channel non-vacuous. Details and the
plan deviation: [`migration_status.md`](migration_status.md) § Scope.

## How to run

```sh
# corpus gate (no cmake needed)
dune exec src/bin/yelu/yelu.exe -- compile-corpus probes/json

# one hybrid cell — cache + codemodel-v2 + ctest
dune exec src/bin/yelu/yelu.exe -- hybrid probes/json
dune exec src/bin/yelu/yelu.exe -- hybrid probes/json -D JSON_Install=OFF

# full matrix (9 options × {ON,OFF} = 18 cells, tripled oracle per cell)
dune exec src/bin/yelu/yelu.exe -- matrix probes/json

# evaluator channel (real cmake vs the in-process evaluator; discovery tool)
dune exec test/test-runcmake/test_json_matrix_smoke.exe
```

## Project spec — user-knob surface

The 11 `option()` declarations in `vendor/json/CMakeLists.txt`.

| name | default | gates |
|---|---|---|
| `JSON_BuildTests` | `${MAIN_PROJECT}` and cmake ≥ 3.13 | `include(CTest)` + `add_subdirectory(tests)` — **held off the matrix** |
| `JSON_CI` | `OFF` | `include(ci)` — **held off the matrix** |
| `JSON_Diagnostics` | `OFF` | `JSON_DIAGNOSTICS=1` interface definition |
| `JSON_Diagnostic_Positions` | `OFF` | `JSON_DIAGNOSTIC_POSITIONS=1` |
| `JSON_GlobalUDLs` | `ON` | `JSON_USE_GLOBAL_UDLS=0` when OFF |
| `JSON_ImplicitConversions` | `ON` | `JSON_USE_IMPLICIT_CONVERSIONS=0` when OFF |
| `JSON_DisableEnumSerialization` | `OFF` | `JSON_DISABLE_ENUM_SERIALIZATION=1` |
| `JSON_LegacyDiscardedValueComparison` | `OFF` | `JSON_USE_LEGACY_DISCARDED_VALUE_COMPARISON=1` |
| `JSON_Install` | `${MAIN_PROJECT}` | the whole `install()`/`export()`/CPack block |
| `JSON_MultipleHeaders` | `ON` | `include/` vs `single_include/` as the build include dir |
| `JSON_SystemInclude` | `OFF` | `SYSTEM` on the interface include dirs |

All nine non-subdirectory options are matrix axes. Note `JSON_MultipleHeaders`
and `JSON_SystemInclude` are cache-visible *and* codemodel-visible (they change
the interface include path / its SYSTEM flag), so the codemodel channel is
load-bearing here, not decorative.

## Adaptation footprint — the 4 raw escapes

Unlike fmt's escapes (3 of which are *by design* — dynamic `${kind}`
visibility), **all four json escapes are recorded gaps**. Each `yc_raw` in
`main.yc` carries an inline `GAP Jn:` comment pointing at
[`migration_status.md`](migration_status.md).

| line | construct | gap |
|---|---|---|
| 1 | `cmake_minimum_required(VERSION 3.5...4.0)` | **J3** — `<min>...<max>` range dropped at emit |
| 7 | `project(nlohmann_json VERSION 3.12.0 LANGUAGES CXX)` | **J4** — `project VERSION` silently dropped; proven divergent |
| ~205 | `export(TARGETS … NAMESPACE … FILE …)` | **J2** — `~targets=[…]` unreachable from the CST path; emits bare `export()` |
| ~210 | `install(TARGETS … EXPORT … INCLUDES DESTINATION …)` | **J1** — no `Iak_includes` in the cmake AST |

A fifth gap, **J5**, is in the *formatter*: `yelu fmt` unquotes a
leading-`${…}` atom containing `::` and the result no longer parses. Because of
it, `main.yc` is intentionally **not** formatter-canonical — do not run
`yelu fmt -w probes/json/main.yc` until J5 is fixed.

Additionally, `target_include_directories(t ${NLOHMANN_JSON_SYSTEM_INCLUDE}
INTERFACE …)` goes through the **by-design** dynamic-visibility raw fallback in
the compiler (no source-level escape needed) — the same mechanism fmt relies on.

## Known limitations

- **`tests/` and `cmake/ci.cmake` untranslated** — so `JSON_BuildTests` /
  `JSON_CI` are not matrix axes. `tests/` still configures (upstream text, both
  sides), which is what makes the ctest channel meaningful.
- **MSVC natvis branch** is translated but never exercised (matrix runs Linux).
  Codegen is verified only insofar as cmake parses it.
- **No build-level oracle.** json is header-only; the meaningful build-level
  check is a *downstream consumer* linking the installed package — which J4
  currently breaks, so that fixture waits on J4.
- **No install channel.** Per charter, nothing is installed; if added it must
  target `_out/json/<tag>/install`, never a bare `cmake --install`.

## Related

- [`migration_status.md`](migration_status.md) — running log + the J1–J5 gap registry
- [`main.json`](main.json) — hybrid/matrix driver configuration
- [`../PROBE_CHARTER.md`](../PROBE_CHARTER.md) — mission, boundaries, pause protocol
- [`../fmt/README.md`](../fmt/README.md) — the worked exemplar this mirrors
- [`../cache_matrix.md`](../cache_matrix.md) — matrix oracle methodology
- [`../../test/test-runcmake/test_json_matrix_smoke.ml`](../../test/test-runcmake/test_json_matrix_smoke.ml) — evaluator-channel smoke
