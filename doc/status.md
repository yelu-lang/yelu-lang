# Status — what is being worked on right now

> **Scope: in-flight work and the immediate queue. Nothing else.**
> This file is deliberately short and self-expiring: when an item finishes it
> leaves here and its record lives in the worklog. If you are looking for
> *why* something is designed a certain way, or a full project audit, this is
> the wrong file — see § Where the durable records live.
>
> Last touched: 2026-07-16.

## In flight

*(nothing — next item is #1 in the queue below)*

**Just landed: Tier (b) is complete.** `Yc_driver.parse_yc` =
`parse_cst ∘ lower_cst` (`237bfb8`), and the dead token-level grammar is
deleted (`cf69703`, 2548 → 1481 lines). `yelu_parse.ml` is no longer a parser
— it is the per-command argument-interpretation library (`_inner` functions:
name → positionals → kwargs → `expr option`) that `Yc_cst_lower` dispatches to.
`open Yelu_lexer` is gone; the file no longer touches tokens.

## Immediate queue (agreed order, 2026-07-16)

These are the yc items that must precede ycn work, because **they touch the
IR** — the shared substrate `Yelu_cmake_convert` (1,889 LOC) maps in both
directions. Pure-*surface* yc items (version literal, `message_*`,
`~mode=Defined`, shape-4 records, …) erase and don't touch the IR, so they can
happen any time, including after ycn starts.

1. ~~Tier (b) sweep~~ — **done** (`cf69703`).
2. **Dead specialized-property commands — decide.** ← *next*
   `set_global_property` / `get_global_property` / `set_directory_property` /
   `get_directory_property` / `set_test_properties` / `set_source_property`
   have **no usable surface**: the positional form rejects (audit #3), no
   labeled form exists, and the bare arity emits nothing, a literal `?`, or
   *crashes emit* (`set_test_properties 'mytest'` →
   `emit_ast: uncovered expr constructor`). They are fully redundant — the
   unified entity form covers all of them
   (`set_property Global|Directory|Test|Source ~property=[…]`, verified).
   They are nonetheless in `command_names` → manifest → TextMate grammar →
   LSP vocabulary → reserved names, **and carry live IR constructors that
   convert already maps** (`ECmakeSetDirectoryProperty`,
   `ECmakeSetSourceProperty`, `ECmakeSetTestsProperties`,
   `ECmakeGetGlobalProperty`, + ycn-side `ESetTestsProperties`).
   Decision needed: **delete**, or **thin aliases** to the unified form.
   Either way it is small; leaving it means ycn inherits phantom constructors.
3. **Raw-escape unification** — one "opaque cmake code" model for
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
