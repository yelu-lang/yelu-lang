# nlohmann/json — probe migration status (running log)

> **Status: first pass COMPLETE.** Root translated, corpus gate wired into
> `dune test`, hybrid matrix **18/18 across all three channels**. Five
> yelu_cmake gaps found and recorded (§ Gaps found) — none patched *by the
> probe*, per [`../PROBE_CHARTER.md`](../PROBE_CHARTER.md).
>
> **Update 2026-07-31 — all five gaps have since been fixed** in a
> human-directed compiler pass. `main.yc` is down from 4 `yc_raw` escapes to
> **zero**: the entire nlohmann/json root now translates through the typed
> surface with no emit warnings. Per-gap fix notes and what fell out of each
> are in [`status.md`](status.md).
>
> **This file is the record — the evidence for each gap**, kept as it was
> measured. The *plan and outcomes* live in [`status.md`](status.md). Start
> there if you are picking up the remaining follow-ups (F1–F4) or the open
> decisions.

## Project & pin

| | |
| --- | --- |
| Project | [nlohmann/json](https://github.com/nlohmann/json) — header-only JSON, INTERFACE-library canon |
| **Pinned tag** | **v3.12.0** |
| **Commit** | `55f93686c01528224f448c19128836e7df245f72` |
| Source | `vendor/json` → `~/code/contrib/json-all/json` (symlink; clean at tag) |
| Build/matrix out | `_out/json/` |
| Root CMakeLists | 225 lines → `main.yc` 173 lines |

## Result

| oracle | result |
| --- | --- |
| `.yc` corpus compile gate (`probes/json/dune`, in `dune test`) | 1/1 ok |
| hybrid matrix — CMakeCache (18 cells) | **18/18** |
| hybrid matrix — file-api codemodel-v2 | **18/18**, 128 codemodel keys, 0 differ |
| hybrid matrix — ctest definitions | **18/18** MATCH (101 tests both sides) |
| generated package files (`…Config.cmake`, `…ConfigVersion.cmake`, `.pc`) | byte-identical — an extra hand check, *not* a matrix channel (this is where J4 hid) |
| installed cmake package (sandboxed prefix, J1 check) | identical, incl. `INTERFACE_INCLUDE_DIRECTORIES` |
| evaluator-channel smoke (`test_json_matrix_smoke.exe`) | 22 cells, median 11 matched, all cells *stable* |
| raw cmake escapes | **0** (was 4; each was a recorded gap, all four now fixed) |

Reproduce:

```sh
dune exec src/bin/yelu/yelu.exe -- compile-corpus probes/json   # gate
dune exec src/bin/yelu/yelu.exe -- hybrid probes/json           # one cell, 3 channels
dune exec src/bin/yelu/yelu.exe -- matrix probes/json           # 18 cells
dune exec test/test-runcmake/test_json_matrix_smoke.exe         # evaluator channel
```

## Scope — root-only first pass

Translated: **only the root `CMakeLists.txt`** → `probes/json/main.yc`.

| upstream | → `.yc` | notes |
| --- | --- | --- |
| `CMakeLists.txt` (225 L) | `probes/json/main.yc` (186 L) | INTERFACE lib + 11 options + install/export block |

**Deviation from the plan, worth knowing.** The plan said the base config would
hold `JSON_BuildTests` OFF so `add_subdirectory(tests)` never fires. In practice
it defaults **ON** (json is the main project and cmake ≥ 3.13), and that is
*better*: `tests/CMakeLists.txt` is upstream text on **both** sides of every
hybrid cell (only the root is spliced), so it is neutral to the comparison —
while making the **ctest channel non-vacuous** (101 tests matched per cell
instead of zero). `JSON_CI` stays OFF (default), so `include(ci)` never fires.
`JSON_BuildTests` / `JSON_CI` are therefore not matrix axes; translating
`tests/` and `cmake/ci.cmake` remains a later pass.

## Matrix axes (9 options — the `main.json` list)

The 9 options that don't pull an untranslated subdirectory, each × {ON, OFF} =
18 cells. `JSON_Install` defaults ON (json is the main project), so the
install/export block is exercised in every cell and additionally flipped.

`JSON_Diagnostics`, `JSON_Diagnostic_Positions`, `JSON_GlobalUDLs`,
`JSON_ImplicitConversions`, `JSON_DisableEnumSerialization`,
`JSON_LegacyDiscardedValueComparison`, `JSON_Install`, `JSON_MultipleHeaders`,
`JSON_SystemInclude`.

## Gaps found (registry-style — recorded, NOT patched)

Five gaps. Two are **silently wrong output** (J2, J4) — the class the charter
exists to surface. None was worked around by changing `src/langs/`; each was
routed through the sanctioned `yc_raw` escape, which warns at emit so the
footprint stayed visible.

> **All five are now fixed** (2026-07-31). The sections below are preserved as
> the *evidence as measured at probe time* — the symptom, the root cause, and
> the divergence numbers. **What was done about each, and what fell out of it,
> is in [`status.md`](status.md)** along with the four follow-ups (F1–F4) that
> were deliberately scoped out.

### J1 — `install(TARGETS … INCLUDES DESTINATION …)` is unmodeled

- **Construct**: `install(TARGETS t EXPORT e INCLUDES DESTINATION d)` (line 210).
- **Symptom**: `yelu compile` **rejects** the labeled form —
  `` `install_targets` does not accept ~includes.destination= — the argument
  would be silently dropped ``. Honest failure, not silent.
- **Root cause**: `Lang_cmake.install_artifact_kind` has no `Iak_includes`
  (`src/langs/cmake/lang_cmake.ml:115`). Worse, if the reject were relaxed,
  `yelu_cmake_emit.ml:955` maps unknown artifact kinds to `| _ ->
  Lang_cmake.Iak_library`, so it would emit `LIBRARY DESTINATION` — wrong output.
- **Repro**: `install_targets $T ~export=$E ~includes.destination=$D`.
- **Fix shape**: add `Iak_includes` to the cmake AST + PP, add `"INCLUDES"` to
  `install_targets`' accepted dotted kinds, and make the emit fallback an error
  rather than `Iak_library`.

### J2 — `export(TARGETS …)` has no reachable yc surface (silently invalid cmake)

- **Construct**: `export(TARGETS t NAMESPACE ns:: FILE f)` (line 205).
- **Symptom**: `export ~targets=[$T] ~namespace='…' ~file=$F` emits a bare
  **`export()`** — invalid cmake, **no warning**.
- **Root cause**: `p_install_command_inner` selects the TARGETS form only on
  `kwarg_opt "targets" = Some (EList targets)`
  (`src/langs/yelu/yelu_parse.ml:1266`), but the CST path never produces an
  `EList`: `Yc_cst_parse.p_args` turns `~targets=[a, b]` into
  `Kw_list ("targets", [a; b])`, and `Yc_cst_lower.convert_args` **flattens** it
  to `[("targets", a); ("targets", b)]`. So the branch is unreachable from any
  `.yc` source; it falls through to the EXPORT-name form with no positional and
  degrades to an empty command.
- **Why the coverage lock missed it**: `test_yelu_cmake_parse.ml` exercises
  `export` through the legacy y1 parser (which does build an `EList`), so the
  command-coverage + dispatch locks are satisfied while the **CST** path is
  broken.
- **Blast radius (audited).** The `Kw_list`-flattening mismatch is a general
  mechanism, but `export` is the only current victim. The other `EList` readers
  in `yelu_parse.ml` are safe: `kw_commands` (lines 453, 1484) uses `kw_all` and
  maps `EList items -> items | e -> [e]`, which handles the flattened form; the
  `~properties={…}` readers (lines 956, 981) match `ERecord`, which arrives via
  `Kw`/`p_atom`, not `Kw_list`. So this is one bug with a latent trap, not a
  broad class.
- **Fix shape**: either have `convert_args` keep `Kw_list` as a single
  `(k, EList …)` pair (and re-check the two `kw_commands` sites, which would
  then see one `EList` of `EList`s), or match the flattened form in the `export`
  `_inner`. The latter is the smaller change.

### J3 — `cmake_minimum_required` `<min>...<max>` range is dropped

- **Construct**: `cmake_minimum_required(VERSION 3.5...4.0)` (line 1).
- **Symptom**: `cmake_minimum_required '3.5...4.0'` emits
  `cmake_minimum_required(VERSION 3.5)`. The IR *carries* the whole string, but
  emit hardcodes `max = None` (`yelu_cmake_emit.ml:341`). Different policy scope
  (upstream sets policies NEW through 4.0; the emit sets only through 3.5) plus
  a cmake 4.3 deprecation warning.
- **Matrix-visible?** No — 18/18 stayed green with the drop in place.
- **Known**: this is the parked **"Version literal"** item in
  [`status.md`](../../doc/status.md) § 7 ("bare version positional is
  accepted-and-dropped today"). json is a concrete consumer.

### J4 — `project(… VERSION …)` is silently dropped (proven divergent)

- **Construct**: `project(nlohmann_json VERSION 3.12.0 LANGUAGES CXX)` (line 7).
- **Symptom**: `ECmakeProject` is constructed with `version = None`
  **unconditionally** (`src/langs/yelu/yelu_parse.ml:1374,1383`), so there is no
  surface that carries it. Writing `project nlohmann_json VERSION '3.12.0' Cxx`
  is worse: the extra positionals become *languages*, emitting
  `project(nlohmann_json LANGUAGES VERSION 3.12.0 CXX)`.
- **Proven divergence** (measured before the `yc_raw` fix):

  | generated file | vanilla cmake | yelu emit |
  | --- | --- | --- |
  | `nlohmann_jsonConfigVersion.cmake` | `set(PACKAGE_VERSION "3.12.0")` | `set(PACKAGE_VERSION "")` |
  | `nlohmann_json.pc` | `Version: 3.12.0` | `Version:` |

  So `find_package(nlohmann_json 3.12.0)` would fail against the yelu-generated
  package while succeeding against upstream.
- **Matrix-visible?** **No — invisible to all three channels.** A useful
  blind-spot datum: the cache/codemodel/ctest triple does not see
  `configure_file` *content*. A fourth channel (diff the generated
  `*Config*.cmake` / `.pc` files) would have caught it; this probe checks them
  by hand instead.
- **Fix shape**: accept a `VERSION` label on `project` (`~version='3.12.0'`) and
  thread it into `ECmakeProject.version` — the emit arm already handles
  `Some v`.

### J5 — `yelu fmt` is not round-trip safe for a leading-`${…}` atom with `::`

- **Repro** (minimal):

  ```
  add_lib_alias '${PROJECT_NAME}::${T}' ~alias_of='${T}'
  ```

  `yelu fmt` prints it **unquoted**:

  ```
  add_lib_alias ${PROJECT_NAME}::${T} ~alias_of='${T}'
  ```

  and re-reading that output fails: `fmt: …: unexpected COLON`.
- **Symptom**: `yelu fmt` output does not re-parse — `fmt ∘ fmt` errors, so
  `yelu fmt -w` on this corpus would corrupt the file.
- **Trigger**: a quoted atom that is *pure interpolation starting with* `${`
  loses its quotes; fmt's `"fmt::${tgt}"` survives because it has a literal
  prefix. The `::` then lexes as `COLON`.
- **Consequence for this probe**: `probes/json/main.yc` is deliberately **not**
  formatter-canonical (it keeps blank lines and section comments). Do not run
  `yelu fmt -w` on it until J5 is fixed.
- **Fix shape**: the CST printer's quote-elision predicate must keep quotes when
  the atom text contains a token-significant character (`:`, `,`, `(`, `)`, …),
  not only when it has a literal prefix.

## Translation notes (non-gaps)

- **`if (POLICY CMP0077)`** → `if policy CMP0077 then ( policy_set CMP0077 NEW )`.
  Emits faithfully (`if (POLICY CMP0077)` / `cmake_policy(SET CMP0077 NEW)`).
  Both plan predictions held; no pause needed.
- **Dynamic `SYSTEM` attribute** — `target_include_directories(t
  ${NLOHMANN_JSON_SYSTEM_INCLUDE} INTERFACE …)` routes through the
  **by-design** dynamic-visibility raw fallback (`is_dynamic_first_item` →
  `ECmakeRawCmd`), the same mechanism as fmt's `setup_target`. It reconstructs
  the command faithfully and is *not* counted among the 4 `yc_raw` escapes (it
  needs no source-level escape). Not a gap.
- **`set(… CACHE INTERNAL "")`** → `cache X := '…' '' ~type=INTERNAL`. `INTERNAL`
  is not in the `~type:` keyword shortlist but passes through the `~type=`
  atom path; `cache_type` is an unvalidated string at emit. Works.
- **`if (CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)`** → `str_eq
  $CMAKE_CURRENT_SOURCE_DIR $CMAKE_SOURCE_DIR`, emitting the quoted-deref form.
  cmake auto-dereferences bare names in `STREQUAL`, so this is semantically
  identical (and the cache/codemodel channels confirm `MAIN_PROJECT` resolves
  the same).
- **stdlib includes** (`ExternalProject`, `GNUInstallDirs`,
  `CMakePackageConfigHelpers`, `CPack`, `CTest`) — emit-only, real cmake
  resolves them. No gap.
- **`configure_file … @ONLY`** ×3 — the third positional carries `@ONLY`; emits
  faithfully.
- **Genex-heavy `target_compile_definitions`** — six `$<$<BOOL:…>:DEF=1>`
  arguments pass through as quoted atoms; cmake sees them identically.

## Evaluator-channel findings (`test_json_matrix_smoke.ml`)

Separate oracle from the hybrid matrix: real cmake vs the **in-process
`Yelu_cmake` evaluator** on the parsed cmake source, cache channel only. 22
cells (json's flippable BOOL/OPTION cache vars minus the two held-out), median
**11** matched, **every cell stable** — i.e. all residual gaps are
config-*independent* constant noise, none load-bearing on an option flip. Three
recurring items, all in the evaluator/bridge (not the emit path this probe
validates):

| item | real | predicted | cause |
| --- | --- | --- | --- |
| `NLOHMANN_JSON_CONFIG_INSTALL_DIR` | `share/cmake/nlohmann_json` | `/cmake/` | `GNUInstallDirs` not evaluated → `CMAKE_INSTALL_DATADIR` unset |
| `JSON_BuildTests` | `ON` | `OFF` | `${CMAKE_VERSION} VERSION_EQUAL/GREATER 3.13` false with `CMAKE_VERSION` unseeded |
| `cond[POLICY CMP0077]` | — | `-> default` | `yelu_cmake_from_emit` does not bridge a `POLICY` condition |

These are the same "Day-1 from_emit scope" class fmt's smoke reports; recorded
for completeness, not blockers for this probe.

## Next (later passes)

Moved to **[`status.md`](status.md)** — the fix queue (J1–J5 in priority order,
with fix shapes and verification recipes) and the four open decisions (4th
matrix channel, `tests/` second pass, `build_equiv/json` fixture, who fixes the
gaps). Kept in one place so it doesn't drift from this record.
