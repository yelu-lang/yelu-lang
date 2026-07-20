# Status — what is being worked on right now

> **Scope: in-flight work and the immediate queue. Nothing else.**
> This file is deliberately short and self-expiring: when an item finishes it
> leaves here and its record lives in the worklog. If you are looking for
> *why* something is designed a certain way, or a full project audit, this is
> the wrong file — see § Where the durable records live.
>
> Last touched: 2026-07-20.

## In flight

**Doc cleanup + test enhancement, before item 3** (agreed 2026-07-20: the
raw-escape unification touches the IR, so tighten the net first).

- **Test enhancement — done.** A coverage scan found 15 of the 138
  `command_names` entries with zero test mention; five were genuinely broken
  (9 `cmake_path` ops silently dropping `~out=`; `add_exe_alias` /
  `add_lib_imported` / `precompile_headers` with **no .yc surface at all**,
  emitting their yc name as bogus cmake; `add_lib_alias` aliasing a target to
  itself). All fixed, and a **command-coverage lock** in
  `test_yelu_cmake_parse.ml` now fails the build if a `command_names` entry
  has no case. 274 → 312 in that suite, ~1034 unit tests overall.
- **Doc cleanup — done.** Test counts (994 → 1034); the `yelu_parse.ml` row
  (it stopped being a parser at Tier (b)); a test-table row naming a file that
  no longer exists; the now-fixed latent deref in `yc_syntax_critique.md`;
  four already-closed rows in `project_overview.md`'s gap table; and a new
  gotcha — *a name in `command_names` is not evidence it is implemented*
  (adding a command takes **three** edits: `command_names`, an `_inner` arm,
  the `yc_cst_lower` family list).
- **One status tracker — done.** `lang/surface_status.md` retired; see the
  note at the bottom of this file.
- **Coverage doc — done, by generating it.**
  [`lang/yc_command_reference.md`](lang/yc_command_reference.md) is emitted by
  `yelu command-reference` from `command_names` × `Yc_cst_lower.family_of` ×
  `command_kwargs`, and freshness-locked by a dune `(diff)` rule. The
  hand-maintained rows in `lang_coverage.md` were the ones that rotted (it
  claimed ~60/~70 commands had a test while 15 had none); that file now keeps
  only its non-derivable half, the cmake test-suite tractability map.
  `project_overview.md` still wants a full body pass at some point — it has a
  delta note at the top for now.

## Immediate queue (agreed order, 2026-07-16)

These are the yc items that must precede ycn work, because **they touch the
IR** — the shared substrate `Yelu_cmake_convert` (1,889 LOC) maps in both
directions. Pure-*surface* yc items (version literal, `message_*`,
`~mode=Defined`, shape-4 records, …) erase and don't touch the IR, so they can
happen any time, including after ycn starts.

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
3. **Raw-escape unification** ← *next* — one "opaque cmake code" model for
   `yc_raw` / `ECmakeRaw` / `ECmakeRawCmd` / hybrid `raw_cmake`. An IR
   consolidation, so it ripples through convert: doing it after ycn starts
   pays that migration twice, and ycn needs its own opacity story anyway —
   better to inherit one concept than four.

**Then:** ycn concrete syntax — the gateway to the whole ycn agenda (records
as values, Y17 typing, Y18 entity value are all unwritable until ycn has a
surface). Design notes:
[`yelu_cmake/ycn_concrete_syntax.md`](yelu_cmake/ycn_concrete_syntax.md);
acceptance corpus already exists (65 hand-written ycn programs in
`test_yelu_lift_lower.ml`).

## Parked — not queued, but not forgotten

Small, independent, and safe to pick up in any order. Each is a *surface* item
(no IR impact) unless noted.

| item | note |
| --- | --- |
| **B2 — token spans on wellform findings** | Findings carry a name, not a span; the LSP scans for the first whole-word match. Heuristic but practical. The located lexer already provides what's needed. |
| **LSP hover / semantic tokens** (M1.5b tail) | Parse-error spans shipped; these two did not. |
| **Statement-level error recovery** (M1.4) | Deferred into the LSP work — only the LSP consumes partial trees, and the formatter is already fail-safe (parse error → no overwrite). Do the light top-level version when the LSP needs it. |
| **Cross-file collect** | The LSP sees one file at a time, so `function`/`macro` declarations behind `include`/`add_subdirectory` read as unknown. Would kill the last open-world false-positive class. |
| **"Did you mean X?"** | Levenshtein against `command_names ∪ defined_names`; cheap addition to the `Unknown_command` text. |
| **Manifest `ctor` column** | Populate + test-lock now that `lower` makes the surface↔constructor link verifiable. |
| **Version literal** | `find_package Foo '9.0'` — the bare version positional is still accepted-and-dropped. |
| **Per-mode `message_*`** | vs today's `~mode=`. |
| **Duplicate single-value field → reject** | Y14 pattern (painpoints #11) for record / dotted-label forms. Adjacent: a wrong-*shaped* `~properties=` (list where a record is expected) is silently dropped — `Unknown_kwarg` can't see it, the key is valid. |
| **`string_json` unknown op** | Fails at emit (`emit_ast: unknown string(JSON …) op`) rather than as a wellform diagnostic. Right error, wrong surface. |
| **"Belief" definition** | Shapes the `check` op's output type — flat diagnostics vs a richer fact stream the LSP renders. See `lang/surface_lsp_framework.md` §4. |

## Where the durable records live

| kind | file |
| --- | --- |
| narrative record of finished work | [`worklog/worklog_2026_06.md`](worklog/worklog_2026_06.md) |
| project-wide audit | [`project_overview.md`](project_overview.md) |
| surface / formatter / LSP **design** (incl. the shipped pipeline, §8) | [`lang/surface_lsp_framework.md`](lang/surface_lsp_framework.md) |
| yc syntax design + open items | [`lang/yc_syntax_critique.md`](lang/yc_syntax_critique.md) |
| yelu_cmake harness tracker | [`yelu_cmake/status.md`](yelu_cmake/status.md) |
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
