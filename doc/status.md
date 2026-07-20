# Status — what is being worked on right now

> **Scope: in-flight work and the immediate queue. Nothing else.**
> This file is deliberately short and self-expiring: when an item finishes it
> leaves here and its record lives in the worklog. If you are looking for
> *why* something is designed a certain way, or a full project audit, this is
> the wrong file — see § Where the durable records live.
>
> Last touched: 2026-07-16.

## In flight

### Tier (b) — retire the legacy parser · **mechanical sweep remaining**

The semantic half is **done** (`237bfb8`): `Yc_driver.parse_yc` is
`parse_cst ∘ lower_cst`, every consumer moved (drivers, the 280-test
per-command suite, wellform tests, `debug_kwarg`), and the emit-bridge oracle
retired with its reference side (superseded by the tripled matrix, which
compares against *real cmake*). The switch caught a real dispatch drift —
`get_property` was missing from `yc_cst_lower.property_names`, so the CST path
silently fell to raw and dropped `~out`.

**Remaining: pure dead-code deletion in `src/langs/yelu/yelu_parse.ml`**
(~900 token-level lines, zero callers).

Delete:
- the tail from `p_cmake_op_command_y1` (~line 1970) to EOF — cond grammar
  (`p_cond_atom_y1` / `p_cond_y1`), stmt grammar (`p_stmt_inner_y1` and its
  `and`-chain: let / if / function / macro / while / foreach / generic / flow /
  apply / block), `p_stmt_y1`, `parse_tokens_y1`, `parse_program_legacy`, the
  `parse_program_y1` alias, and the `let () =` forward-ref population block;
- the scattered per-family dispatchers `p_*_command_y1` (the `toks`-taking
  wrappers — *not* the `_inner`s);
- `p_assign_y1` + the three `*_fwd` forward refs (~lines 197-206);
- `collect_command_args`, `p_expr_y1`, `fallback_to_raw`.

Keep (these are what `yc_cst_lower` calls — verify with
`grep -oE "P\.[a-z_0-9]+" src/langs/yelu/yc_cst_lower.ml | sort -u`):
- the 12 `p_*_command_y1_inner` functions;
- their expr-level helpers: `split_by_keywords`, `out_var_y1`,
  `p_cmake_entity`, `str_of`, `cmake_name_of_yelu`, `message_modes`,
  `target_groups_to_y1`, `cvar_name_of_y1`, … (anything an `_inner` references).

Method: **Edit tool only, never sed** (per the Gotchas — sed cannot see
match-case scope). Delete in chunks; `dune build` + full `dune test` after
each. The compiler is the safety net: an over-delete is an unbound-value
error, not silent breakage.

## Immediate queue (agreed order, 2026-07-16)

These are the yc items that must precede ycn work, because **they touch the
IR** — the shared substrate `Yelu_cmake_convert` (1,889 LOC) maps in both
directions. Pure-*surface* yc items (version literal, `message_*`,
`~mode=Defined`, shape-4 records, …) erase and don't touch the IR, so they can
happen any time, including after ycn starts.

1. **Tier (b) sweep** — above, in flight.
2. **Dead specialized-property commands — decide.**
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
