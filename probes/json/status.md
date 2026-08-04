# json probe — open work & fix queue

> **The handoff tracker for the json probe.** What the probe found, in priority
> order, with the fix shape and how each was verified. The *evidence* (symptom,
> root cause, measured divergence) lives in
> [`migration_status.md`](migration_status.md) § Gaps found — this file is the
> *plan*, that file is the *record*.
>
> The probe agent that found these is bound by
> [`../PROBE_CHARTER.md`](../PROBE_CHARTER.md) and **may not touch
> `src/langs/`**, so they were handed off as plans. **The handoff has since
> been actioned: J1–J5 are all fixed** (human-directed compiler pass,
> 2026-07-31). What remains open is the follow-ups and decisions below.

## Probe status: first pass COMPLETE — all five gaps fixed

| bar (charter § Definition of done)      | result                                                                            |
| --------------------------------------- | --------------------------------------------------------------------------------- |
| root `CMakeLists.txt` → `.yc`, faithful | ✅ 225 L → 173 L `main.yc`, **zero `yc_raw` escapes**, no emit warnings            |
| corpus-compile gate in `dune test`      | ✅ 1/1 ok                                                                          |
| matrix N/N × 3 channels                 | ✅ **18/18** cache · **18/18** codemodel-v2 (128 keys, 0 differ) · **18/18** ctest |
| every gap recorded, not worked around   | ✅ 5 gaps (J1–J5) recorded, then **all 5 fixed**                                   |

Branch `probe/json`. Not pushed. Probe landed at `9ddf42b`; the fixes are
`3ac570b` (J2+J4), `4233183` (J1), `f4dd0be` (J5), `9f4dd23` (J3).

The probe was green *with* the gaps present (every one routed through `yc_raw`
or an honest reject), which is what made the fixes safe to do afterwards and in
any order. It is now green with **no escapes at all** — the whole nlohmann/json
root goes through the typed surface.

**Regression evidence carried by every fix commit**: `dune test` green,
`yelu matrix probes/json` 18/18, `yelu matrix probes/fmt` 24/24 (the
emit-touching regression check), and — for the gaps the matrix is blind to —
the generated `*Config*.cmake` / `.pc` files byte-identical, plus a sandboxed
install diff for J1.

## Fix queue (priority order)

Priority is by **failure mode**, not by size: silently-wrong output first,
loud-failure second, cosmetic last.

| #   | gap                                                | failure mode                                                   | size | status                                            |
| --- | -------------------------------------------------- | -------------------------------------------------------------- | ---- | ------------------------------------------------- |
| 1   | **J2** `export(TARGETS …)`                         | 🔴 silent — emits invalid cmake, no warning                     | S    | ✅ **fixed**                                       |
| 2   | **J4** `project(… VERSION …)`                      | 🔴 silent — drops the version, breaks `find_package(pkg <ver>)` | S    | ✅ **fixed**                                       |
| 3   | **J1** `install(TARGETS … INCLUDES DESTINATION …)` | 🟡 loud — honest reject at emit                                 | M    | ✅ **fixed**                                       |
| 4   | **J5** `yelu fmt` unquotes `${…}::${…}`            | 🟡 loud — output fails to re-parse                              | S    | ✅ **fixed**                                       |
| 5   | **J3** `cmake_minimum_required <min>...<max>`      | 🟡 quiet-but-known — range dropped                              | M    | ✅ **fixed** (range half of *Version literal*)     |

> **Two printer bugs fell out of J2/J4** — both latent because nothing could
> reach the field: `export(TARGETS …)` fused the last target into the following
> keyword (`${T}NAMESPACE ns::`) and `project(…)` fused the version into it
> (`VERSION 3.12.0LANGUAGES CXX`). Same root cause in both: `pp_with_key` /
> `pp_list_with_key` carry a **trailing but no leading** separator, so
> concatenating them with `%a%a` in a format string relies on the preceding
> printer to supply one. Worth a look if another dormant field is ever woken up.

### 1. J2 — `export(TARGETS …)` emits a bare `export()` — ✅ FIXED

**Landed**: the `export` `_inner` now collects *all* `"targets"` kwargs and
accepts both shapes (flattened pairs from the CST path, a single `EList` from
the legacy y1 path), so the TARGETS form is reachable from `.yc`. `~namespace=`
also learned `EVarLookup` (json passes `'${PROJECT_NAME}::'`). Plus the
`Export_targets` printer separator bug this uncovered. `probes/json/main.yc`
now uses the typed `export ~targets=[…] ~namespace= ~file=`; matrix still 18/18,
fmt still 24/24.

The plan that was carried out is kept below for context.

**Fix shape (smaller of two).** In `src/langs/yelu/yelu_parse.ml`
(`p_install_command_inner`, ~line 1266) the TARGETS form is selected on
`kwarg_opt "targets" = Some (EList targets)`. The CST never produces that:
`Yc_cst_parse.p_args` builds `Kw_list ("targets", [...])` and
`Yc_cst_lower.convert_args` flattens it to repeated `("targets", v)` pairs.
Match the **flattened** form instead — collect with a `kw_all`-style helper and
accept both shapes so the legacy y1 path keeps working.

The alternative — make `convert_args` keep `Kw_list` as one `(k, EList …)`
pair — is the more principled fix but wider: it changes what *every* `~key=[…]`
label lowers to, so the two `kw_commands` sites (`yelu_parse.ml:453`, `:1484`)
would then see one `EList` of `EList`s and need re-checking.

**Blast radius, already audited** (so nobody has to re-do it): `export` is the
only victim. `kw_commands` maps `EList items -> items | e -> [e]` and tolerates
the flattened form; the `~properties=` readers (`:956`, `:981`) match `ERecord`,
which arrives via `Kw`/`p_atom`, not `Kw_list`.

**Why the locks missed it** — worth fixing alongside: the command-coverage lock
in `test_yelu_cmake_parse.ml` drives the **legacy y1 parser**, which *does*
build an `EList`, so `export` looks covered while the CST path is broken. Any
future `_inner` that reads a kwarg shape the two parsers disagree on has the
same hole. Consider adding a CST-path assertion for `export` when fixing.

**Verify**: in `probes/json/main.yc`, replace the `yc_raw` at the `export(...)`
line with

```
export ~targets=[$NLOHMANN_JSON_TARGET_NAME] ~namespace='${PROJECT_NAME}::' ~file=$NLOHMANN_JSON_CMAKE_PROJECT_TARGETS_FILE;
```

then `yelu compile probes/json/main.yc` must emit the full
`export(TARGETS … NAMESPACE … FILE …)`, and `yelu matrix probes/json` must stay
18/18.

### 2. J4 — `project(… VERSION …)` is silently dropped — ✅ FIXED

**Landed**: `project` accepts `~version=` (registered in
`Yc_primitives.command_kwargs`, command-reference promoted), and a positional
`VERSION` / `DESCRIPTION` / `HOMEPAGE_URL` / `LANGUAGES` is now a fatal
positional reject instead of being swept into *languages*. The two arms merged
into one (`name_e :: langs` covers `langs = []` identically). Plus the `Project`
printer separator bug this uncovered. **Verified the way the matrix cannot**:
`nlohmann_jsonConfigVersion.cmake`, `nlohmann_json.pc` and
`nlohmann_jsonConfig.cmake` are now byte-identical between the vanilla and
yelu-emitted builds.

`DESCRIPTION` / `HOMEPAGE_URL` still have no surface — `ECmakeProject` carries
no field for them, so they route to `yc_raw` **loudly** now rather than
mis-emitting. That is a smaller, separate gap if anyone wants it.

The plan that was carried out is kept below for context.

**Fix shape.** `ECmakeProject` is constructed with `version = None`
**unconditionally** at `src/langs/yelu/yelu_parse.ml:1374` and `:1383`. Accept a
`~version=` label and thread it through — the emit arm
(`yelu_cmake_emit.ml:346`) already handles `Some v` via
`Lang_cmake_utils.version_of_string`. Guard the positional form too: today
`project nlohmann_json VERSION '3.12.0' Cxx` silently turns the extra
positionals into *languages* and emits
`project(nlohmann_json LANGUAGES VERSION 3.12.0 CXX)`. That should be a
positional reject in the Step-2 style, like the other labeled-only commands.

**Verify**: replace the `yc_raw` at the `project(...)` line in `main.yc` with
`project nlohmann_json Cxx ~version='3.12.0';` (or whatever surface lands), then
check the generated files converge — this is the check the matrix cannot make:

```sh
dune exec src/bin/yelu/yelu.exe -- hybrid probes/json
diff _out/json/yelu/build-cmake/nlohmann_jsonConfigVersion.cmake \
     _out/json/yelu/build-yelu/nlohmann_jsonConfigVersion.cmake
diff _out/json/yelu/build-cmake/nlohmann_json.pc \
     _out/json/yelu/build-yelu/nlohmann_json.pc
```

Both must be empty. Before the `yc_raw` workaround they differed:
`PACKAGE_VERSION "3.12.0"` vs `""`, and `Version: 3.12.0` vs `Version:`.

### 3. J1 — `install(TARGETS … INCLUDES DESTINATION …)` — ✅ FIXED

**Landed**, and the design question below was resolved the way it suggested:
`INCLUDES DESTINATION` is **not** an artifact kind. It became a dedicated
`includes_destination : arg list` field on `Lang_cmake.Install_targets` (and
`expr list` on `ECmakeInstallTargets`), printed after the per-kind clauses per
cmake's grammar. Surface is the flat label `~includes_destination=` (scalar or
list), *not* the dotted `~includes.destination=` — the dotted lane means
"artifact kind", which this isn't.

**A second, larger silent bug came out with it.** The emit's artifact-kind map
had no arms for `OBJECTS`, `FRAMEWORK`, `BUNDLE`, `RESOURCE` or
`CXX_MODULES_BMI` — all five are *accepted* dotted labels
(`Yc_primitives.install_artifact_kinds`), and all five fell into
`| _ -> Iak_library`, silently emitting `LIBRARY DESTINATION`. So
`~resource.destination='res'` installed to the library destination. All five
arms added; the fallback is now a hard `failwith`, because a wrong install
destination stays invisible until someone actually installs.

**Verified past the matrix**, since this clause only materializes in the
*installed* export file: installed both builds into a throwaway
`_out/json/install-check/` prefix (never system-wide, per charter) and diffed —
`share/cmake/nlohmann_json/` is identical, with
`INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include;…"` present on both
sides. Matrix 18/18, fmt 24/24.

**Known lossy edges, deliberately not chased** (both mirror the existing
`exclude_from_all` ycn deferral in `lang_coverage.md`):
- the **ycn normal form** doesn't carry `includes_destination`, so
  `from_normal` reconstructs `[]`;
- the **cmake text→AST parser** still doesn't recognize `INCLUDES`
  (`kind_of` returns `None` → `take_clauses` bails, so the command falls back
  wholesale rather than being parsed and silently stripped — lossy but safe).
  Teaching `cmake_text_parse` this clause is a small follow-up.

The original plan is kept below for context.

**Fix shape.** Three edits: add `Iak_includes` to
`Lang_cmake.install_artifact_kind` (`src/langs/cmake/lang_cmake.ml:115`) and its
printer arm (`lang_cmake_pp.ml:~1326`); accept `"INCLUDES"` as a dotted kind in
`install_targets`' `art_kw` list (`yelu_parse.ml:~1160`); and — independently
worth doing — replace the emit fallback at `yelu_cmake_emit.ml:964`
(`| _ -> Lang_cmake.Iak_library`) with an error, since it silently turns any
unrecognized kind into `LIBRARY`.

Note `INCLUDES DESTINATION` is not an artifact clause in cmake's grammar (it
sets `INTERFACE_INCLUDE_DIRECTORIES` on the exported target, and takes a *list*
of destinations), so a dedicated field may model it better than reusing the
artifact-clause list. Decide that before writing the AST node.

**Verify**: replace the `yc_raw` in `main.yc`, re-run `yelu matrix probes/json`
(18/18) and diff `nlohmann_jsonTargets.cmake` between the two build dirs — its
`INTERFACE_INCLUDE_DIRECTORIES` line is what this clause produces.

### 4. J5 — `yelu fmt` breaks `'${A}::${B}'` — ✅ FIXED

**Landed**, and the diagnosis in the plan below was close but not exact. The
culprit was **`is_bare_name`**, not the `A_eval` value-position arm: value slots
were always quoting correctly (`a := '${A}::${B}'` round-trips fine). Only
**name/target slots** — the assignment LHS and the first positional of a target
command — go through `is_bare_name`, which tested `String.is_prefix n "$"` and
so waved through *any* `$`-starting text. Its own comment already warned about
this hazard for the non-`$` half (`fmt::fmt-c` must stay quoted).

New `eval_text_is_bare_safe`: text is bare-printable only if every character
**outside** a `${…}` / `$<…>` group is bare-safe (groups nest, so
`$<BUILD_INTERFACE:${DIR}>` is handled). `${A}/inc` still elides; `${A}::${B}`
keeps its quotes.

**Regression test**: `test_yc_cst_bridge.ml` → `elision` →
`"name-slot quote retention (fmt re-parses)"`, including the `fmt ∘ fmt = fmt`
property that actually failed. It needs its own surface-level test because
quoting is invisible to the emit oracle (emit is byte-identical either way) —
the standing "surface changes are blind to the emit oracle" gotcha.

**No churn**: swept `yelu fmt` over every `.yc` under `probes/`, `examples/` and
`test/fixtures/` — all re-parse, all idempotent, and the already-canonical
`probes/fmt` corpus is unchanged. `probes/json/main.yc` may now be safely
`fmt -w`'d (it is still kept un-canonical on purpose, to preserve its blank
lines and section comments).

The original diagnosis is kept below for context.

**Fix shape.** The CST printer's quote-elision predicate drops quotes on an atom
that is pure interpolation starting with `${`. It must instead keep quotes
whenever the atom text contains a token-significant character (`:`, `,`, `(`,
`)`, `~`, …). fmt's `"fmt::${tgt}"` survives only because a literal prefix keeps
it in the quoted lane — that's luck, not a rule.

**Repro** (self-contained):

```sh
printf "add_lib_alias '\${PROJECT_NAME}::\${T}' ~alias_of='\${T}'\n" > /tmp/a.yc
dune exec src/bin/yelu/yelu.exe -- fmt /tmp/a.yc > /tmp/b.yc
dune exec src/bin/yelu/yelu.exe -- fmt /tmp/b.yc   # → fmt: /tmp/b.yc: unexpected COLON
```

**Consequence today**: `probes/json/main.yc` is deliberately **not**
formatter-canonical (it keeps blank lines and section comments). **Do not run
`yelu fmt -w probes/json/main.yc` until this is fixed** — it would corrupt the
file. Once fixed, an idempotency check (`fmt ∘ fmt == fmt`) over the probe
corpora would be a cheap permanent guard.

### 5. J3 — `cmake_minimum_required` `<min>...<max>` range dropped — ✅ FIXED

**Landed** exactly as planned: split on `"..."` before `version_of_string`
(which itself truncates a range to its min), mirroring `policy_version`. The
cmake AST and printer already modelled the range — only the emit arm dropped
it. `probes/json/main.yc` sheds its last `yc_raw`, and the cmake 4.x
deprecation warning that the narrowed `VERSION 3.5` provoked is gone from both
sides of the hybrid configure. fmt's `'3.8...3.28'` now emits its range too;
matrix still 24/24.

**Only the range half** of the parked *Version literal* item is done. The other
half — the accepted-and-dropped bare version positional on
`find_package Foo '9.0'` — is a surface-side concern and is untouched.

The original plan is kept below for context.

Already tracked as the parked **Version literal** item in
[`../../doc/status.md`](../../doc/status.md) § 7; json is now a concrete
consumer and that row points back here.

**Fix shape.** The IR *carries* the whole `"3.5...4.0"` string
(`ECmakeMinimumRequired`), but emit hardcodes `max = None`
(`yelu_cmake_emit.ml:341`). Split the range the way `policy_version` already
does (`yelu_parse.ml:1429` splits on `"..."`) and pass `max`. Same treatment
covers `find_package Foo '9.0'`.

**Verify**: `yelu compile` must emit `cmake_minimum_required(VERSION 3.5...4.0)`
verbatim, and the cmake 4.3 deprecation warning ("Compatibility with CMake <
3.10 will be removed") must disappear from the hybrid configure log.

## Follow-ups left open by the fix pass

Small, self-contained, none blocking. Each was scoped *out* deliberately, not
missed.

| #   | item                                                            | why it was left                                                                                                                                                                                                 | shape                                                                                    |
| --- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| F1  | **`cmake_text_parse` doesn't recognize `INCLUDES DESTINATION`** | J1 was an *emit* gap; the text→AST direction bails safely (`kind_of "INCLUDES"` → `None` → `take_clauses` returns `None` → the command falls back wholesale) rather than parsing and silently stripping         | teach `take_clauses` the clause; it needs a 4th component threaded through the recursion |
| F2  | **ycn doesn't carry `includes_destination`**                    | `EInstallTargets` has no field, so `from_normal` rebuilds `[]` — the *same* deferral `exclude_from_all` already has in `lang_coverage.md`; the yc→cmake emit path is faithful, only the ycn round-trip is lossy | do it with the ycn agenda, alongside `exclude_from_all`                                  |
| F3  | **`project(… DESCRIPTION / HOMEPAGE_URL …)` has no surface**    | `ECmakeProject` carries no field for them. After J4 they are a **loud** positional reject instead of silently becoming *languages*, so nothing is silently wrong                                                | mirror `~version=`: add fields + labels; `Lang_cmake.Project` already has both           |
| F4  | **`find_package Foo '9.0'` still drops its version**            | the other half of the parked *Version literal* item; J3 only fixed the `<min>...<max>` range                                                                                                                    | surface-side; see `doc/status.md` § 7                                                    |

## Open decisions (need a human)

| # | decision | recommendation |
| --- | --- | --- |
| D1 | **4th matrix channel over generated files?** | **Yes** — but scope it as *generated files*, not *`configure_file` outputs*. Measured detail in § D1. |
| D2 | **Second pass — translate `tests/` + `cmake/ci.cmake`?** | **Yes for `tests/`, separately for `ci.cmake`.** They are very different jobs; split into D2a / D2b. Detail in § D2. |
| D3 | **`build_equiv/json` fixture (charter's optional 2nd bar)?** | **Unblocked — J4 and J1 were its blockers.** json is header-only, so the meaningful build-level artifact is a *downstream consumer* linking the installed package; that needed a correct package version (J4) and a correct `INTERFACE_INCLUDE_DIRECTORIES` (J1). The sandboxed install diff done for J1 is most of the fixture already. **D2a and D3 reinforce each other** — see § D2. |
| D4 | ~~Should the probe agent fix J1–J5?~~ | **Resolved**: done as a human-directed compiler pass, 2026-07-31. All five fixed; see the queue above. |

### D1 — a generated-file channel: what it watches, and what it is worth

**What json actually generates.** Three `configure_file(… @ONLY)` calls, all
unconditional (they run even with `JSON_Install=OFF`), plus one file written by
`export(TARGETS …)`:

| generator | output (in the build dir) | substituted / derived from |
| --- | --- | --- |
| `configure_file cmake/pkg-config.pc.in` | `nlohmann_json.pc` | `@CMAKE_INSTALL_PREFIX@` `@CMAKE_INSTALL_INCLUDEDIR@` `@PROJECT_NAME@` `@PROJECT_VERSION@` |
| `configure_file cmake/nlohmann_jsonConfigVersion.cmake.in` | `nlohmann_jsonConfigVersion.cmake` | `@PROJECT_VERSION@` `@PROJECT_VERSION_MAJOR@` |
| `configure_file cmake/config.cmake.in` | `nlohmann_jsonConfig.cmake` | `@PROJECT_NAME@` `@NLOHMANN_JSON_TARGET_NAME@` `@NLOHMANN_JSON_TARGETS_EXPORT_NAME@` |
| `export(TARGETS …)` | `nlohmann_jsonTargets.cmake` | the target's exported interface |

**The class it catches.** Every `@VAR@` above is an *ordinary* cmake variable —
not a cache entry, not a target property, not a test. The three existing
channels see cache entries, codemodel structure, and ctest definitions
respectively, so **a normal variable is invisible to all of them**.
`configure_file` is the one place those values become observable. That is
precisely why J4 (`PROJECT_VERSION` silently empty) sat green at 18/18 while
breaking `find_package(nlohmann_json 3.12.0)` for every consumer.

**Measured: is it worth doing *per cell*?** I diffed all four generated files
across a base run and four option flips:

| flip | `.pc` | `ConfigVersion` | `Config` | `Targets.cmake` |
| --- | --- | --- | --- | --- |
| `JSON_MultipleHeaders=OFF` | same | same | same | **differs** (`include/` → `single_include/`) |
| `JSON_Diagnostics=ON` | same | same | same | **differs** (`$<$<BOOL:OFF>:JSON_DIAGNOSTICS=1>` → `BOOL:ON`) |
| `JSON_SystemInclude=ON` | same | same | same | same |
| `JSON_Install=OFF` | same | same | same | **absent** |

So the honest answer is a **split verdict**:

- the three `configure_file` outputs are **cell-invariant** for json (they
  depend only on `PROJECT_*` / `CMAKE_INSTALL_*`, none option-driven) —
  diffing them 18× would be 18× redundant;
- `nlohmann_jsonTargets.cmake` **is cell-sensitive**, and it is also where J1's
  `INCLUDES DESTINATION` lands.

**Therefore scope the channel as "every generated file in the build dir"**
(glob the `configure_file` outputs *and* the `export()` output), and run it per
cell — justified by the export file, not by `configure_file`. A cheaper variant
— check generated files **once per project** rather than per cell — would still
have caught J4 in full, and is worth considering if per-cell cost matters.

**Implementation note, the only real cost**: `nlohmann_jsonTargets.cmake`
embeds absolute source paths, which differ by construction between the vendor
tree and the hybrid worktree (`/home/red/code/contrib/json-all/json/include/`
vs `…/_out/json/yelu/source/include/`). A naive diff false-positives on every
cell. It needs the same path normalization the cache channel already applies —
that, not the diffing, is the work.

### D2 — what `tests/` is, and what translating it buys

**Yes, `tests/` is json's own internal suite** — not a third-party harness. It
splits into three groups with very different translation value. Full
file-by-file inventory with line counts and reachability:
[`migration_status.md`](migration_status.md) § Raw-cmake inventory.

| group | files | what it is |
| --- | --- | --- |
| **unit tests** | `tests/CMakeLists.txt` (197 L) + `cmake/test.cmake` (273 L) + `cmake/download_test_data.cmake` (56 L) | doctest-based; `file(GLOB src/unit-*.cpp)` × up to 5 C++ standards via `json_test_add_test_for`. **This is where the 101 ctest entries the probe already matches come from.** doctest / fifo_map are vendored header-only — include dirs, no `add_subdirectory` |
| **ABI compat** | `tests/abi/` + `config/` `diag/` `inline_ns/` (83 L total) | builds the same TU twice with different macros and links them |
| **cmake integration** | 6 × `tests/cmake_*/CMakeLists.txt` (114 L total) | **the interesting group** — see below |

**The integration group is the reason to do this.** Those six dirs verify
json's *packaging*: `cmake_import`, `cmake_import_minver`,
`cmake_add_subdirectory`, `cmake_fetch_content`, `cmake_fetch_content2`,
`cmake_target_include_directories`. They are upstream's own oracle for exactly
what J4 and J1 broke — `cmake_import*` are gated on `JSON_Install` and consume
the generated `nlohmann_jsonConfig.cmake`, and `cmake_import_minver` does a
*versioned* `find_package`, which the empty `PACKAGE_VERSION` from J4 would
have failed outright.

That makes **D2a and D3 mutually reinforcing**, as you say: the integration
tests are a packaging oracle expressed in cmake, and `build_equiv/json` is the
same idea expressed as a fixture. Doing D2a gives D3 its assertions for free.

**Caveats to plan around, not discovered late:**

- Each `tests/cmake_*/CMakeLists.txt` is only the *harness half*. The
  `project/` subdir beside it is **not** `add_subdirectory`'d — it is a
  separate root project that a nested `cmake` launches at **test-run** time via
  `add_test`. A configure-time matrix never sees it. Getting real value needs
  the tests actually **run**, or the `project/` dirs treated as their own tiny
  probes.
- `file(GLOB src/unit-*.cpp)` in `tests/CMakeLists.txt` — a glob is a
  translation hazard worth flagging up front (yc has `file_glob`).
- **Good news on scope**: the two heavy dirs are *not* reachable from the root.
  `tests/benchmarks/` (`FetchContent` → `google/benchmark`, i.e. **network**)
  and `tests/cuda_example/` are only invoked by `cmake/ci.cmake` custom targets
  as separate cmake processes. A `JSON_BuildTests=ON` pass pulls neither.

**Split D2, because the two halves are not the same job:**

| | scope | size | verdict |
| --- | --- | --- | --- |
| **D2a** | `tests/` + `cmake/test.cmake` + `download_test_data.cmake` | **~723 L** across 13 files | **Do it.** Makes `JSON_BuildTests` a real matrix axis and brings upstream's packaging oracle into range |
| **D2b** | `cmake/ci.cmake` + `clang_flags.cmake` + `gcc_flags.cmake` | **~1081 L** across 3 files | **Defer.** 40+ `add_custom_target` developer conveniences (lint, coverage, sanitizers, per-compiler builds) that launch nested cmake processes; `gcc_flags.cmake` alone is 348 L of warning-flag lists. Not part of json's consumable build, and it is the single largest file in the project |

## Regression guards this probe leaves behind

Anyone changing emit should re-run these, not just `dune test`:

```sh
dune exec src/bin/yelu/yelu.exe -- compile-corpus probes/json  # in dune test
dune exec src/bin/yelu/yelu.exe -- matrix probes/json          # 18/18, NOT in dune test
dune exec test/test-runcmake/test_json_matrix_smoke.exe        # median ≥ 11, NOT in dune test
```

`test/test-runcmake/test_json_matrix_smoke.ml` carries a `median_floor = 11`
constant — the evaluator-channel level recorded when the probe landed. **Raise
it when the evaluator improves; never lower it silently.**

## Related

- [`migration_status.md`](migration_status.md) — the running log: the
  **raw-cmake inventory & translation coverage table** (D2's sizing), full gap
  evidence (symptoms, root causes, measured divergences), translation notes,
  evaluator-channel findings
- [`README.md`](README.md) — probe landing page: status table, option surface
- [`../../doc/yelu_cmake/lang_coverage.md`](../../doc/yelu_cmake/lang_coverage.md)
  § Emit / semantic coverage gaps — J1, J2, J4, J5 in the predictor-wide
  registry (all now marked fixed)
- [`../../doc/status.md`](../../doc/status.md) § 7 — the **Version literal**
  row, now naming J3's consumer
- [`../PROBE_CHARTER.md`](../PROBE_CHARTER.md) — the boundaries that make every
  item here a handoff rather than a patch
