# json probe — open work & fix queue

> **The handoff tracker for the json probe.** What the probe found that someone
> else has to fix, in priority order, with the concrete fix shape and how to
> verify it. The *evidence* for each item (symptom, root cause, measured
> divergence) lives in [`migration_status.md`](migration_status.md) § Gaps
> found — this file is the *plan*, that file is the *record*.
>
> Written by the probe agent, which is bound by
> [`../PROBE_CHARTER.md`](../PROBE_CHARTER.md) and **may not touch
> `src/langs/`**. Every item below is therefore unfixed by design, not by
> oversight.

## Probe status: first pass COMPLETE — nothing blocking

| bar (charter § Definition of done) | result |
| --- | --- |
| root `CMakeLists.txt` → `.yc`, faithful | ✅ 225 L → 186 L `main.yc` |
| corpus-compile gate in `dune test` | ✅ 1/1 ok |
| matrix N/N × 3 channels | ✅ **18/18** cache · **18/18** codemodel-v2 (128 keys, 0 differ) · **18/18** ctest |
| every gap recorded, not worked around | ✅ 5 gaps (J1–J5), 4 `yc_raw` escapes, each with an inline `GAP Jn:` comment |

Branch `probe/json`, commit `9ddf42b`. Not pushed.

The probe is green **with** the gaps present — all five are routed through
`yc_raw` or an honest reject. Fixing them is about the *compiler*, not about
unblocking this probe.

## Fix queue (priority order)

Priority is by **failure mode**, not by size: silently-wrong output first,
loud-failure second, cosmetic last.

| # | gap | failure mode | size | status |
| --- | --- | --- | --- | --- |
| 1 | **J2** `export(TARGETS …)` | 🔴 silent — emits invalid cmake, no warning | S | ✅ **fixed** |
| 2 | **J4** `project(… VERSION …)` | 🔴 silent — drops the version, breaks `find_package(pkg <ver>)` | S | ✅ **fixed** |
| 3 | **J1** `install(TARGETS … INCLUDES DESTINATION …)` | 🟡 loud — honest reject at emit | M | ✅ **fixed** |
| 4 | **J5** `yelu fmt` unquotes `${…}::${…}` | 🟡 loud — output fails to re-parse | S | ✅ **fixed** |
| 5 | **J3** `cmake_minimum_required <min>...<max>` | 🟡 quiet-but-known — range dropped | M | ⬜ open — with the parked **Version literal** item |

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

### 5. J3 — `cmake_minimum_required` `<min>...<max>` range dropped

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

## Open decisions (need a human)

| # | decision | recommendation |
| --- | --- | --- |
| D1 | **Add a 4th matrix channel: diff `configure_file` outputs per cell?** | **Yes.** J4 is a demonstrated blind spot — an install-breaking divergence that cache + codemodel + ctest all missed. The hybrid driver already walks both build dirs for the file-api reply; globbing the generated `*Config*.cmake` / `*.pc` and diffing them is a small addition. Touches `src/bin/yelu/yelu.ml` (infra) → not the probe agent's call. |
| D2 | **Second pass — translate `tests/` + `cmake/ci.cmake`?** | **Not next.** It would make `JSON_BuildTests` / `JSON_CI` real matrix axes, but `tests/` is many subdirs with thirdparty deps. Fixing J2/J4 is higher value per hour. |
| D3 | **`build_equiv/json` fixture (charter's optional 2nd bar)?** | **After J4.** json is header-only, so the meaningful build-level artifact is a *downstream consumer* linking the installed package — which is exactly what J4 breaks. Building the fixture first would just encode the bug. |
| D4 | **Should the probe agent fix any of J1–J5?** | **No** — charter boundary (`src/langs/` is off-limits). J2 + J4 as one human-directed compiler pass is the recommended shape; both are small and both currently produce silently wrong cmake. |

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

- [`migration_status.md`](migration_status.md) — the running log: full gap
  evidence (symptoms, root causes, measured divergences), translation notes,
  evaluator-channel findings
- [`README.md`](README.md) — probe landing page: status table, option surface,
  the 4 raw escapes
- [`../../doc/yelu_cmake/lang_coverage.md`](../../doc/yelu_cmake/lang_coverage.md)
  § Emit / semantic coverage gaps — J1, J2, J4, J5 registered in the
  predictor-wide registry
- [`../../doc/status.md`](../../doc/status.md) § 7 — the **Version literal**
  row, now naming J3's consumer
- [`../PROBE_CHARTER.md`](../PROBE_CHARTER.md) — the boundaries that make every
  item here a handoff rather than a patch
