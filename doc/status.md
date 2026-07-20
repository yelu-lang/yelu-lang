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

- **Test enhancement — done.** A coverage scan found 15 of ~119
  `command_names` entries with zero test mention; five were genuinely broken
  (9 `cmake_path` ops silently dropping `~out=`; `add_exe_alias` /
  `add_lib_imported` / `precompile_headers` with **no .yc surface at all**,
  emitting their yc name as bogus cmake; `add_lib_alias` aliasing a target to
  itself). All fixed, and a **command-coverage lock** in
  `test_yelu_cmake_parse.ml` now fails the build if a `command_names` entry
  has no case. 274 → 312 in that suite, ~1034 unit tests overall.
- **Doc cleanup — in progress.** Done: test counts (994 → 1034), the
  `yelu_parse.ml` row (it stopped being a parser at Tier (b)), the test-table
  row naming a file that no longer exists, the now-fixed latent deref in
  `yc_syntax_critique.md`, and a new gotcha — *a name in `command_names` is
  not evidence it is implemented* (adding a command takes **three** edits:
  `command_names`, an `_inner` arm, the `yc_cst_lower` family list).
  Remaining: `lang_coverage.md` (snapshot is 2026-05-20) and a
  `project_overview.md` pass (last full audit 2026-06-21, predates the audit
  fixes and Tier (b)).

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

## Where the durable records live

| kind | file |
| --- | --- |
| narrative record of finished work | [`worklog/worklog_2026_06.md`](worklog/worklog_2026_06.md) |
| project-wide audit | [`project_overview.md`](project_overview.md) |
| surface / formatter / LSP tracker | [`lang/surface_status.md`](lang/surface_status.md) |
| yelu_cmake harness tracker | [`yelu_cmake/status.md`](yelu_cmake/status.md) |
| numbered backlog (Y2…Y18) + handoff | [`../CLAUDE.md`](../CLAUDE.md) |
| layer triage rule (yc vs ycn) | [`lang/yc_ycn_boundary.md`](lang/yc_ycn_boundary.md) |

**Keeping this honest:** when an item lands, delete it from here and write it
up in the worklog. If this file ever describes something already shipped, it
has failed at its one job.
