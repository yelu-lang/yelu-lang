# json — predictor probe

> **Project**: [nlohmann/json](https://github.com/nlohmann/json) — header-only
> JSON for Modern C++
> **Vendored at**: `vendor/json` → `/home/red/code/contrib/json-all/json`
> **Pin**: tag **v3.12.0**, commit `55f93686c01528224f448c19128836e7df245f72`
> **Why this probe**: the INTERFACE-library canon. A compact 225-line root with
> 11 options, a full Config-package `install()`/`export()` block, genex-driven
> compile definitions, and a dynamic `SYSTEM` include attribute — the shapes fmt
> (a compiled library) never exercised.

## Status (2026-07-31) — first pass complete, all five gaps fixed

| oracle | result |
|---|---|
| `.yc` corpus compile gate (`dune test`) | 1/1 ok |
| matrix — CMakeCache (18 cells) | **18/18** |
| matrix — file-api codemodel-v2 | **18/18**, 128 keys, 0 differ |
| matrix — ctest definitions | **18/18** MATCH (101 tests both sides) |
| generated package files (extra hand check) | `…Config.cmake`, `…ConfigVersion.cmake`, `.pc` byte-identical |
| installed cmake package (sandboxed prefix) | identical, incl. `INTERFACE_INCLUDE_DIRECTORIES` |
| evaluator-channel smoke | 22 cells, median 11 matched, all cells stable |
| raw cmake escapes | **0** — was 4; every one was a recorded gap, all now fixed |

**Verdict: complete first pass.** The root `CMakeLists.txt` has a `.yc`
equivalent that parses, wellforms, and emits; the emitted cmake is
configure-equivalent to upstream across all 18 option cells on all three
channels. Five yelu_cmake gaps were found and recorded, **none** patched by the
probe (charter boundary) — and **all five have since been fixed** in a
human-directed compiler pass, so the whole root now translates through the
typed surface with no raw escapes and no emit warnings.

> **Picking up the remaining work? → [`status.md`](status.md).** It carries the
> J1–J5 outcomes (what was fixed, what fell out of each), the four follow-ups
> deliberately scoped out (F1–F4), and the open decisions.
> `migration_status.md` is the evidence behind it.

## Layout

```
probes/json/
├── main.json              ← driver config: project, source_dir, out_root, 9 matrix options
├── dune                   ← corpus-compile gate (copied verbatim from probes/fmt/dune)
├── main.yc                ← CMakeLists.txt (173 lines .yc ← 225 lines cmake)
├── README.md              ← this file (landing page)
├── status.md              ← J1–J5 outcomes, F1–F4 follow-ups, open decisions
└── migration_status.md    ← running log + gap evidence
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

## Adaptation footprint — zero raw escapes

`main.yc` needs **no `yc_raw` at all**, and compiles with no emit warnings.
That is the outcome of fixing the gaps, not of the first translation: the probe
originally carried **4** escapes, one per gap, each with an inline `GAP Jn:`
comment. Unlike fmt's escapes — 3 of which are *by design* (dynamic `${kind}`
visibility) — none of json's were stylistic; every one marked a real compiler
gap, which is why the count could go to zero.

| upstream construct | was | gap → now |
|---|---|---|
| `cmake_minimum_required(VERSION 3.5...4.0)` | `yc_raw` | **J3** fixed → `cmake_minimum_required '3.5...4.0'` |
| `project(nlohmann_json VERSION 3.12.0 LANGUAGES CXX)` | `yc_raw` | **J4** fixed → `project nlohmann_json Cxx ~version='3.12.0'` |
| `export(TARGETS … NAMESPACE … FILE …)` | `yc_raw` | **J2** fixed → `export ~targets=[…] ~namespace= ~file=` |
| `install(TARGETS … EXPORT … INCLUDES DESTINATION …)` | `yc_raw` | **J1** fixed → `install_targets … ~export= ~includes_destination=` |

A fifth gap, **J5**, was in the *formatter*: `yelu fmt` unquoted a
leading-`${…}` atom containing `::` and the result no longer parsed. Also fixed,
so `main.yc` is now safe to `yelu fmt -w` — it is nevertheless kept
un-canonical on purpose, to preserve its blank lines and `##` section comments.

`target_include_directories(t ${NLOHMANN_JSON_SYSTEM_INCLUDE} INTERFACE …)`
still goes through the **by-design** dynamic-visibility raw fallback inside the
compiler (no source-level escape needed) — the same mechanism fmt relies on.
That one is not a gap.

## Known limitations

- **`tests/` and `cmake/ci.cmake` untranslated** — so `JSON_BuildTests` /
  `JSON_CI` are not matrix axes. `tests/` still configures (upstream text, both
  sides), which is what makes the ctest channel meaningful.
- **MSVC natvis branch** is translated but never exercised (matrix runs Linux).
  Codegen is verified only insofar as cmake parses it.
- **No build-level oracle yet.** json is header-only, so the meaningful
  build-level check is a *downstream consumer* linking the installed package.
  That was blocked on J4 (empty package version) and J1 (missing
  `INTERFACE_INCLUDE_DIRECTORIES`); both are fixed, so a
  `test/fixtures/build_equiv/json/` fixture is now unblocked — the sandboxed
  install diff done to verify J1 is most of it already.
- **No install channel in the matrix.** Nothing is installed per cell. The J1
  verification installed into a throwaway `_out/json/install-check/` prefix —
  per charter, never a bare `cmake --install`.
- **The three matrix channels do not see `configure_file` content** — J4 lived
  there undetected. Until a generated-file channel exists (decision D1 in
  [`status.md`](status.md)), that check is a manual step.

## Related

- [`status.md`](status.md) — **the tracker**: J1–J5 outcomes (what was fixed,
  what fell out of each), the F1–F4 follow-ups scoped out, and the open decisions
- [`migration_status.md`](migration_status.md) — running log + the J1–J5 gap
  evidence as originally measured
- [`main.json`](main.json) — hybrid/matrix driver configuration
- [`../PROBE_CHARTER.md`](../PROBE_CHARTER.md) — mission, boundaries, pause protocol
- [`../fmt/README.md`](../fmt/README.md) — the worked exemplar this mirrors
- [`../cache_matrix.md`](../cache_matrix.md) — matrix oracle methodology
- [`../../test/test-runcmake/test_json_matrix_smoke.ml`](../../test/test-runcmake/test_json_matrix_smoke.ml) — evaluator-channel smoke
