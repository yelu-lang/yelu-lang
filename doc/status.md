# Status — what is being worked on right now

> **Scope: in-flight work and the immediate queue. Nothing else.**
> This file is deliberately short and self-expiring: when an item finishes it
> leaves here and its record lives in the worklog. If you are looking for
> *why* something is designed a certain way, or a full project audit, this is
> the wrong file — see § Where the durable records live.
>
> Last touched: 2026-07-21.

## In flight

*(nothing active — next is ycn concrete syntax; see the queue below)*

**Recently landed (2026-07-20..21), for context — full detail in the worklog:**
- **Coverage/dispatch locks + 5 fixed bugs.** A scan found 15 of 138
  `command_names` entries untested and 5 broken (9 `cmake_path` ops dropping
  `~out=`; `add_exe_alias` / `add_lib_imported` / `precompile_headers` with no
  `.yc` surface at all; `add_lib_alias` self-aliasing). Guards added: the
  command-coverage lock, the dispatch lock, and a generated
  `yc_command_reference.md`.
- **Doc consolidation.** Counts refreshed; `surface_status.md` retired into
  three homes (design → `surface_lsp_framework.md` §8, history → worklog, open
  items → this file § Parked); `project_overview.md` full body pass.
- **Wrong-shaped `~properties=` + orphan deletion** — see queue item 3.

## Immediate queue

1. ~~Tier (b) sweep~~ — **done** (`cf69703`).
2. ~~Dead specialized-property commands~~ — **done** (`1d70486`). Removed the
   *text surface* only; the IR constructors stay (15 programmatic users:
   step_common_ir, CMakeOnly generators, runcmake tests, legacy bridge) — the
   earlier "delete them, they're redundant" plan was scoped too wide. Behavior
   now splits on whether the name is real cmake: `get_directory_property`
   passes through as raw (it is a builtin, in the stdlib cache), the other five
   report "unknown command" (they were never cmake commands). Found and fixed
   an adjacent live bug on the way (`cc196c1`): `set_source_files_properties`
   emitted `${BMI}PROPERTIES` — token-merged, silently losing the keyword.
3. ~~Wrong-shaped `~properties=` silent drop~~ + ~~orphaned `yelu_emit_main.ml`~~
   — **done** (`1db4bd6`, `c751713`). A list where a record was required
   collapsed the whole command to `ESeq []` (emitted nothing, exit 0); now a
   fatal `Malformed_kwarg` CST check. Deleting `yelu_emit_main.ml` also killed
   the phantom "hybrid `raw_cmake`" concept (it was a one-line dead alias to
   `yc_raw`).

### Raw-escape unification — re-scoped 2026-07-21, no longer a hard pre-req

The 2026-07-16 framing ("unify four concepts; IR consolidation that **ripples
through `Yelu_cmake_convert`**; must precede ycn") was investigated and is
**overstated**:

- **Two live constructors, not four.** `ECmakeRaw` (verbatim-text codegen
  escape) and `ECmakeRawCmd` (structured parser fallback), both yc-side.
  `yc_raw` is just the surface command that builds `ECmakeRaw`; "hybrid
  `raw_cmake`" was a dead alias, now deleted.
- **It does not ripple through convert.** Neither raw constructor appears in
  `Yelu_cmake_convert` — they hit its `| _ -> fail "cannot translate unknown
  yelu_cmake expression"` catch-all. Raw literally cannot cross into ycn today.
- So the real fact is **ycn has no opacity escape at all**. That is a *design*
  question best answered *with* ycn's surface, not as a standalone gate before
  it. Unifying `ECmakeRaw`/`ECmakeRawCmd` now, in isolation, buys little and
  can't be validated against ycn's needs because ycn's opacity story doesn't
  exist yet.

**Decision:** de-prioritized. Fold the raw-escape design into ycn's opacity
escape when ycn concrete syntax starts, rather than doing a standalone yc-side
consolidation first. The two yc-side constructors are not causing bugs.

**So the real next big rock is ycn concrete syntax** — the gateway to the whole
ycn agenda (records as values, Y17 typing, Y18 entity value are all unwritable
until ycn has a surface). Design notes:
[`yelu_cmake/ycn_concrete_syntax.md`](yelu_cmake/ycn_concrete_syntax.md);
acceptance corpus already exists (65 hand-written ycn programs in
`test_yelu_lift_lower.ml`).

## Parked — not queued, but not forgotten

Small, independent, and safe to pick up in any order. Each is a *surface* item
(no IR impact) unless noted.

*Surface-syntax design rationale for these lives in
[`lang/yc_syntax_critique.md`](lang/yc_syntax_critique.md); this is just the
task list.*

| item | note |
| --- | --- |
| **B2 — token spans on wellform findings** | Findings carry a name, not a span; the LSP scans for the first whole-word match. Heuristic but practical. The located lexer already provides what's needed. |
| **LSP hover / semantic tokens** (M1.5b tail) | Parse-error spans shipped; these two did not. |
| **Statement-level error recovery** (M1.4) | Deferred into the LSP work — only the LSP consumes partial trees, and the formatter is already fail-safe (parse error → no overwrite). Do the light top-level version when the LSP needs it. |
| **Cross-file collect** | The LSP sees one file at a time, so `function`/`macro` declarations behind `include`/`add_subdirectory` read as unknown. Would kill the last open-world false-positive class. |
| **"Did you mean X?"** | Levenshtein against `command_names ∪ defined_names`; cheap addition to the `Unknown_command` text. |
| **Manifest `ctor` column** | Populate + test-lock now that `lower` makes the surface↔constructor link verifiable. |
| **Version literal** | `cmake_minimum_required 3.8...3.25` / `find_package Foo '9.0'` — a first-class unquoted version literal (lexer token `N(.N)*(...N(.N)*)?`); the bare version positional is currently accepted-and-dropped. |
| **Per-mode `message_*`** | terse `message_fatal`/`_warning`/`_status` aliases desugaring to `~mode=` (curated subset). |
| **`get_property ~mode=Defined`** | the trailing `SET`/`DEFINED`/`BRIEF_DOCS`/`FULL_DOCS` flag-as-kwarg-enum; ~30 lines, get_property only. |
| **shape-4 install_targets records** | `~library={destination=…}` — the dotted-label stopgap stands; the record form is the postponed upgrade. |
| **function labeled args** | `fun f(~x)` / call `f ~x='v'` — needs generated `cmake_parse_arguments`; ties to **Y15**. |
| **`Apply_shadows_primitive` first-class message** | the check fires only as a buried generic warning, unlike `Raw_cmake_escape`/`Positional_form`; give it its own message. (`add_custom_command` gap already fixed, `d60190f`.) |
| **Duplicate single-value field → reject** | Y14 pattern (painpoints #11) for record / dotted-label forms. (The adjacent wrong-*shaped* `~properties=` silent drop is fixed — `Malformed_kwarg`, `1db4bd6`.) |
| **cache docstring `~doc:`** + **property cache-semantics test** (Value vs SET vs DEFINED) | small cosmetics. |
| **`string_json` unknown op** | Fails at emit (`emit_ast: unknown string(JSON …) op`) rather than as a wellform diagnostic. Right error, wrong surface. |
| **"Belief" definition** | Shapes the `check` op's output type — flat diagnostics vs a richer fact stream the LSP renders. See `lang/surface_lsp_framework.md` §4. |

**ycn-ward redesigns** (not surface polish — need a value/type model, so they
belong to the ycn agenda per [`lang/yc_ycn_boundary.md`](lang/yc_ycn_boundary.md)):
records-as-first-class-values, value-default reads (bare `foo` = value), dotted
globals (`$cmake.version`). Design context in
[`lang/yc_syntax_critique.md`](lang/yc_syntax_critique.md) and
[`lang/var_centric_design.md`](lang/var_centric_design.md).

## Where the durable records live

| kind | file |
| --- | --- |
| narrative record of finished work | [`worklog/worklog_2026_06.md`](worklog/worklog_2026_06.md) |
| project-wide audit | [`project_overview.md`](project_overview.md) |
| surface / formatter / LSP **design** (incl. the shipped pipeline, §8) | [`lang/surface_lsp_framework.md`](lang/surface_lsp_framework.md) |
| yc syntax design + open items | [`lang/yc_syntax_critique.md`](lang/yc_syntax_critique.md) |
| yelu_cmake harness backlog / open-work registry | [`yelu_cmake/status.md`](yelu_cmake/status.md) |
| numbered backlog (Y2…Y18) + handoff | [`../CLAUDE.md`](../CLAUDE.md) |
| layer triage rule (yc vs ycn) | [`lang/yc_ycn_boundary.md`](lang/yc_ycn_boundary.md) |

> **One tracker.** `lang/surface_status.md` was retired 2026-07-20 and folded
> into the three files above (design → framework §8, history → worklog,
> open items → this file). It had become ~95% finished work, and a second
> "living tracker" is exactly how the Tier (b) state ended up recorded in
> three drifting places. If a surface question needs a tracker again, it
> belongs *here*, not in a new file.

**Keeping this honest:** when an item lands, delete it from here and write it
up in the worklog. If this file ever describes something already shipped, it
has failed at its one job.
