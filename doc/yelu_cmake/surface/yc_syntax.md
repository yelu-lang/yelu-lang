# yc surface syntax — design & rationale

> **The go-to doc for the `.yc` surface.** What the syntax is, why it's shaped
> that way, and where it read badly before the two surface passes fixed it.
> Companion docs: parser/formatter/LSP *machinery* →
> [`surface_lsp_framework.md`](surface_lsp_framework.md) §8; casing lanes →
> [`casing_design.md`](casing_design.md); the open task list →
> [`status.md`](../../status.md) § Parked; the shipped arc + commits →
> [worklog 2026-06](../../worklog/worklog_2026_06.md).
>
> Syntax evolution is a safe, mechanical operation: accept a cleaner form,
> `yelu fmt -w probes/**/*.yc` to canonicalize, and the **surface-regression
> goldens** (`test_yc_cst_bridge`) + the **fmt matrix** (`yelu matrix
> probes/fmt`, 24/24) prove the emitted cmake is byte-unchanged. `fmt` is
> **pass-through** (no positional→labeled codemod): a positional file is
> rejected at compile, not silently rewritten.

## What works (keep)

- **Structured control flow** — `if c then ( … ) else ( … )`,
  `foreach x in … ( … )`, `fun f(p) ( … )`. No `endif`/`endforeach`; real
  nesting. A decisive win over cmake.
- **Conditions as expressions** — `if ver_lt $V '3.12'`, `if not (defined X)`,
  `a and b or c`. Kills cmake's stringly `if(A AND NOT B)` + implicit-deref
  footguns. The single biggest improvement.
- **`option NAME 'help' DEFAULT`** and **`:=`** read cleanly.

## Inelegances → what fixed them

The original critique split the surface's inelegances by root cause. Resolution:

| inelegance | resolution |
| --- | --- |
| `target` tag noise (`compile_opts target fmt …`) | ✅ implicit target — the tag is dropped |
| three keyword mechanisms (`~out:` / bare `COMMAND` / `:PRIVATE`) | ✅ unified — casing lanes + the `~`-half (below) |
| `'single'` vs `"double"` strings (a non-distinction) | ✅ one canonical form (prefer `'…'`, fall back to `"…"`) |
| `${VAR}` on every read | **defended** (explicit read = correctness) + lightened with `$foo` brace-elision sugar |
| `set_target_properties` PROPERTY repetition; cache docstring as a bare positional | ✅ `~properties={…}` record; cache `~doc:` is still a minor open item |

## The design (durable rationale)

**Casing lanes** — full design in [`casing_design.md`](casing_design.md).
Surface *shape* = the token's *role*: enum choices are leading-cap constructors
(`Public`, no colon), reads are sigiled (`$foo`), reserved-word shadowing is a
hard reject (Y14). All surface transforms; emit is exact cmake.

**The `~`-half — labeled arguments.** One marker `~` (explicit beats
context-sensitive; LLM-friendly), spanning every cmake keyword arg:

- **flag** — `~before`, `~optional` (boolean, present/absent)
- **value** — `~key=value`. `=` not `:`: `:` reads as type ascription (`x: T`),
  `=` as binding — and one rule, `key=value` binds everywhere (labels, records,
  dotted `~library.destination=`).
- **list** — `~key=[a, b, c]`, one comma form. Emit is keyword-driven
  (`COMMAND`→space args, list keyword→`;`-list), so a second separator buys no
  semantics (the reasoning that also collapsed `'`/`"`).
- emit **uppercases the key** (`~before`→`BEFORE`; cmake keyword args are
  case-sensitive).

**Recursive value grammar** — the value after `~label=` is JSON-flavoured, which
is the single change that carried the structured shapes:

```
value := scalar              -- $x, 'str', Foo, 42
       | [ value, value, … ] -- list (elements are values → nesting)
       | { key=value, … }    -- record
```

- **shape 2 (repeated→list)** via singular/plural: `~command=[…]` is one command
  (a token list), `~commands=[[…], […]]` a list of commands, arity-picked by the
  formatter. Carries the per-COMMAND grouping the flat kwarg form lost.
- **shape 3 (record)** `set_target_properties t ~properties={version=$v,
  sources=[a, b]}` — values nest. Records use `=` and **lowercase keys** (emit
  uppercases — same lane as labels, tableless).
- **shape 4 (nested record-list)** install_targets uses the *flat dotted label*
  stopgap (`~library.destination=$d`); the record form (`~library={…}`) is the
  postponed upgrade.

**Metaprogramming → raw, not a bespoke syntax.** cmake lets a `$var` hold *code*
— argument terms spliced *before* parsing (e.g. `$INSTALL_FILE_SET` expands to
`FILE_SET;fmt;DESTINATION;…`, reconstituting a clause). The labeled surface
structurally **cannot** carry a term-valued splice (it isn't one `~key=value`,
and the splice's position is meaning the kwarg form discards). Decision: such
lines go in the existing **`yc_raw`** escape bucket — *not* a bespoke `~raw=`.
The convergence worth noting: the only corpus lines the labeled surface couldn't
express were exactly these metaprogramming/nested corners.

**`?key=default`** reserved for later optional-with-default function params
(arrives with `cmake_parse_arguments` codegen, not now).

## Both surface passes complete

The **no-ALL_CAPS `~`-half** and the **labeled-only Step 2** both shipped
(2026-06-19): the corpus reads as `~flag` / `~label=value` / `~label=[list]` /
`~properties={record}` or explicit `yc_raw`; positional cmake-keyword forms are
a compile error (reject, not raw); `fmt` is pass-through. Full arc + commits in
[worklog 2026-06](../../worklog/worklog_2026_06.md); machinery in
[`surface_lsp_framework.md`](surface_lsp_framework.md) §8; empirical cmake
ground truth (repeated-keyword last-wins vs accumulate) in
[painpoints.md §11](../../cmake/painpoints.md).

> **Verification reminder:** `yelu matrix probes/fmt` (real cmake configure) is
> the only oracle that catches emit-invalid cmake — it is **NOT** in `dune
> test` (which compares parse paths to each other). Run it after any
> emit-touching change. (A property-family regression once shipped 0/24 yet
> green-on-`dune test` because the matrix wasn't run; `f1296a4`.)

## Open threads

The concrete surface-polish backlog (version literal, per-mode `message_*`,
`~mode=Defined`, shape-4 records, function labeled args, `~doc:`, the
`Apply_shadows_primitive` message, …) is the task list in
[`status.md`](../../status.md) § Parked — this doc keeps only the design
*rationale* behind them.

Two design directions worth stating here (the rest are one-liners in the
tracker):

- **Metaprogramming → raw, not bespoke syntax.** Term-valued splices
  (`$INSTALL_FILE_SET` → `FILE_SET;fmt;DESTINATION;…`) can't be one
  `~key=value`, so they live in the `yc_raw` escape bucket. The convergence
  worth noting: the only corpus lines the labeled surface couldn't express were
  exactly these. Unifying the raw-escape constructors into one opaque model is
  parked into ycn (it needs ycn's opacity story; see
  [`status.md`](../../status.md) § Raw-escape).
- **Records: literal is yc, value is ycn.** The record *literal as argument*
  (`~properties={k=v}`, the queued shape-4 `~library={…}`) stays **yc** — it
  erases to a keyword run. Records as *first-class values* (bind / pass /
  project a `{…}`), value-default reads, and dotted globals need a value/type
  model → **ycn**, per [`yc_ycn_boundary.md`](../../yelu_cmake_normal/typing/yc_ycn_boundary.md). The boundary
  is the value flow, not the braces.

(Several latent emit bugs that this section used to track — the literal-target
`${}` deref, the wrong-shaped `~properties=` silent drop — were fixed in the
2026-07 honest-emit / `Malformed_kwarg` work.)

## Related

- [`surface_lsp_framework.md`](surface_lsp_framework.md) §8 — the parser /
  formatter / LSP machinery this design evolves on top of.
- [`casing_design.md`](casing_design.md) — the casing lanes in full.
- [`worklog_2026_06.md`](../../worklog/worklog_2026_06.md) — the shipped arc.
- [`painpoints.md`](../../cmake/painpoints.md) — cmake ground-truth (incl. §11).
- [`driver.md`](../ir/driver.md) — the
  `text ↔ cst_lite ↔ expr` forms the changes touch.
