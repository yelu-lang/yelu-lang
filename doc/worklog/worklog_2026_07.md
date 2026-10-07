# Worklog — July 2026

## 2026-07-28/31: nlohmann/json probe — first pass, then the five gaps it found

The second whole-project probe after fmt, and the first to be run by a
handoff-mode agent against [`probes/PROBE_CHARTER.md`](../../probes/PROBE_CHARTER.md).
Landing page: [`probes/json/README.md`](../../probes/json/README.md).

**Why json.** The INTERFACE-library canon. A compact 225-line root with 11
options, a full Config-package `install()`/`export()` block, genex-driven
compile definitions, and a dynamic `SYSTEM` include attribute — the shapes fmt
(a compiled library) never exercised.

### Probe (first pass, `9ddf42b`)

Pinned v3.12.0 (`55f9368`), root-only scope.

| oracle | result |
| --- | --- |
| `.yc` corpus compile gate (in `dune test`) | 1/1 ok |
| matrix — CMakeCache | **18/18** |
| matrix — file-api codemodel-v2 | **18/18**, 128 keys, 0 differ |
| matrix — ctest definitions | **18/18** MATCH (101 tests both sides) |

Two things worth remembering from the run:

- **The plan said hold `JSON_BuildTests` OFF; reality was better.** It defaults
  ON, so `tests/` configures — from *upstream* text on both sides of every cell
  (only the root is spliced), which keeps it neutral to the comparison while
  making the ctest channel non-vacuous. Zero tests became 101.
- **A fourth, hand-run check earned its place.** The three matrix channels do
  not see `configure_file` *content*, so the generated
  `…Config.cmake` / `…ConfigVersion.cmake` / `.pc` were diffed by hand. That is
  where J4 was hiding, green at 18/18.

### The five gaps, and the fixes

Recorded by the probe (which may not touch `src/langs/`), then fixed in a
human-directed pass. Registry rows: [`lang_coverage.md`](../yelu_cmake/lang_coverage.md)
§ Emit / semantic coverage gaps. Per-gap outcomes:
[`probes/json/status.md`](../../probes/json/status.md).

| gap | failure mode | fix |
| --- | --- | --- |
| **J2** `export(TARGETS …)` | 🔴 **silent** — emitted a bare `export()`, no warning | `3ac570b` |
| **J4** `project(… VERSION …)` | 🔴 **silent** — dropped the version; `find_package(pkg <ver>)` fails against the output | `3ac570b` |
| **J1** `install(TARGETS … INCLUDES DESTINATION …)` | 🟡 loud — honest reject at emit | `4233183` |
| **J5** `yelu fmt` unquoted `${A}::${B}` | 🟡 loud — output would not re-parse | `f4dd0be` |
| **J3** `cmake_minimum_required <min>...<max>` | 🟡 quiet-but-known — range dropped | `9f4dd23` |

`probes/json/main.yc` went from 4 `yc_raw` escapes to **zero**: the whole
nlohmann/json root now translates through the typed surface with no emit
warnings.

### What the fixes taught, beyond the fixes

- **J2 is a lock blind spot, not just a bug.** The `export` `_inner` selected
  the TARGETS form on `Some (EList …)`, but the CST path never builds one —
  `p_args` makes a `Kw_list` and `convert_args` flattens it to repeated
  `(k, v)` pairs. The command-coverage lock passed anyway, because
  `test_yelu_cmake_parse` drives the **legacy y1 parser**, which *does* build an
  `EList`. Audited the rest: `export` was the only victim.
- **Three latent bugs fell out, each unreachable until a fix woke its field.**
  `pp_with_key` / `pp_list_with_key` carry a trailing but no *leading*
  separator, so `"%a%a"` concatenation fused tokens —
  `export(TARGETS ${T}NAMESPACE ns::)` and
  `project(p VERSION 3.12.0LANGUAGES CXX)`. And while auditing J1: the emit's
  artifact-kind map had **no arms** for `OBJECTS` / `FRAMEWORK` / `BUNDLE` /
  `RESOURCE` / `CXX_MODULES_BMI` — all five are *accepted* dotted labels, and
  all five fell into `| _ -> Iak_library`, so `~resource.destination='res'`
  silently installed to the library destination. Arms added; the fallback is
  now a hard `failwith`.
- **Two gaps were invisible to all three channels.** J4's divergence showed up
  only in `configure_file` output; J1's only in the *installed* export file
  (verified by installing both builds into a throwaway
  `_out/json/install-check/` prefix — never system-wide, per charter). This is
  the argument for a generated-file channel (D1 below).

### Open, deliberately

[`probes/json/status.md`](../../probes/json/status.md) carries four follow-ups
scoped out on purpose (F1 `cmake_text_parse` still bails on `INCLUDES`;
F2 ycn doesn't carry `includes_destination`; F3 `project DESCRIPTION` /
`HOMEPAGE_URL` have no surface; F4 `find_package Foo '9.0'` still drops its
version) and three decisions, of which two measured out differently than they
were first framed:

- **D1 — generated-file matrix channel.** Measured: json's three
  `configure_file` outputs are **cell-invariant**, so diffing them per cell is
  18× redundant; but `nlohmann_jsonTargets.cmake` (from `export(TARGETS …)`,
  not `configure_file`) **is** cell-sensitive and is where J1 lands. So scope
  the channel as *generated files*, not *`configure_file` outputs*. The one
  real cost: that file embeds absolute source paths that differ
  vendor-vs-worktree by construction, so it needs the cache channel's path
  normalization or it false-positives every cell.
- **D2 — translate `tests/`.** Split: **D2a** `tests/` (~723 L / 13 files) is
  worth doing, because the six `tests/cmake_*/` dirs are upstream's own
  packaging oracle — `cmake_import_minver` does a *versioned* `find_package`,
  exactly what J4 broke. **D2b** `ci.cmake` + flag files (~1081 L) defer.
- **D3 — `build_equiv/json` fixture.** Unblocked; J4 and J1 *were* its
  blockers, and the sandboxed install diff from J1 is most of the fixture.

Translation-coverage accounting (all 42 cmake files in the tree, grouped by
reachability) is in
[`probes/json/migration_status.md`](../../probes/json/migration_status.md)
§ Raw-cmake inventory. The honest denominator is the 14 files a root configure
actually reaches: **225 / 948 lines, 24%**.

---

## 2026-08-05/07: ycn theory-decomposition review (checkpoint, open)

Recovered from the working tree and committed in `60cd56f`; see that commit
message for exactly what state it is in. The short version: before giving ycn a
concrete syntax, decide whether the 16-fragment decomposition is the substrate
to build on. Evidence is a runnable AST probe
(`src/bin/debug/debug_ycn_decomp.ml`, 18 hand-built ycn programs, no concrete
syntax needed). The review names 7 seams and recommends *improve in place,
defer any semantic re-cut until Y17*.

**§ 8 of the review is an empty decision template.** Filling it is the next
action — it gates steps 2–6 of the ycn sequence.
