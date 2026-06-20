# yc surface syntax — critique & design

> Where the `.yc` surface read well, where it read badly, and the design that
> fixed it. **Both surface passes are complete:** the no-ALL_CAPS pass (the
> `~`-half) *and* the labeled-only pass (Step 2 — positional cmake-keyword forms
> are a compile error; every command with a labeled surface is labeled-only).
> The shipped arc + commits are archived in
> [worklog 2026-06](../worklog/worklog_2026_06.md). This doc keeps the durable
> *design rationale* and the *open items*; it is the syntax-design companion to
> [`surface_status.md`](surface_status.md) (the parser / formatter / LSP
> *machinery*). Syntax evolution is a safe, mechanical operation: accept a
> cleaner form, `yelu fmt -w probes/**/*.yc` to canonicalize, and the
> **emit-bridge** (`test_yc_cst_bridge`) + the **fmt matrix**
> (`yelu matrix probes/fmt`, 24/24) prove the emitted cmake is byte-unchanged.
> Note `fmt` is now **pass-through** (no positional→labeled codemod): a
> positional file is rejected at compile, not silently rewritten.

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

## Status — no-ALL_CAPS pass ✅ complete (2026-06-19)

The `~`-half shipped across every command in `probes/fmt/main.yc`; the full arc
and commits are in [worklog 2026-06](../worklog/worklog_2026_06.md). The corpus
now reads as `~flag` / `~label=value` / `~label=[list]` / `~properties={record}`
or explicit `yc_raw`. Empirical cmake ground truth (repeated-keyword last-wins
vs accumulate) recorded as [painpoints.md §11](../cmake/painpoints.md).

**Verification reminder:** `yelu matrix probes/fmt` (real cmake configure) is the
only oracle that catches emit-invalid cmake — it is **NOT** part of `dune test`
(which compares parse paths to each other). Run it after any emit-touching
change. (A property-family regression shipped 0/24 yet green-on-`dune test`
because the matrix wasn't run; fixed `f1296a4`.)

## Open / remaining

- ✅ **Labeled-only pass — done (2026-06-19).** Positional cmake-keyword forms
  are a compile error (reject, not raw); `fmt` is pass-through. Every command
  with a labeled surface is labeled-only; the deferred list is cleared. Arc in
  [worklog 2026-06](../worklog/worklog_2026_06.md); machinery in
  [`surface_status.md`](surface_status.md).
- **Surface polish (noted 2026-06-19, no hurry):**
  - **version literal** — `cmake_minimum_required '3.8...3.25'` smuggles a cmake
    `min...max` sub-grammar inside a string. Make a version a first-class
    *unquoted literal* (`cmake_minimum_required 3.8...3.25`); a lexer token for
    `N(.N)*(...N(.N)*)?`. Generalizes to `find_package` /
    `write_basic_package_version_file` versions.
  - **per-mode message commands** — terse aliases for the common modes
    (`message_fatal` / `message_warning` / `message_status` / maybe
    `message_debug`) desugaring to `message ~mode=…`, since the mode is the
    prominent token. Curated subset only (not CHECK_*/AUTHOR_WARNING). Additive
    sugar over the `~mode=` general form. (Rationale + boundary in
    [`casing_design.md`](casing_design.md).)
- **Code cleanup (noted 2026-06-19):**
  - **`Apply_shadows_primitive` check holes** — `command_names`
    ([`yc_primitives.ml`](../../src/langs/yelu/yc_primitives.ml)) is missing
    `add_custom_command` (so `ECmakeApply "add_custom_command"` slips through);
    and the error is surfaced only as a buried generic warning, unlike
    `Raw_cmake_escape` / `Positional_form`. Give it a first-class message.
    (Raw-cmake-name applys like `install`/`file`/`cmake_policy` can't be caught
    by name — only proper re-encoding fixes those.) Note: `command_names` is
    co-truth-locked to the manifest, so any addition needs `Yc_manifest` +
    `dune promote`.
  - **`Yelu_emit_main` orphaned** — the legacy OCaml-DSL whole-file emitters
    (`probes/fmt/{main,test_main,compile_error_test}.ml`) were retired
    (superseded by the `.yc` corpus); `Yelu_emit_main` now has no code
    consumers (only `probes/fmt/migration_status.md` references it). Retire
    candidate.
- **Postponed structured forms:**
  - shape-4 install_targets artifact **records** (`~library={destination=…}`) —
    the dotted-label stopgap + the metaprogramming guard stand for now;
  - get_property **`~mode=Defined`** micro-slice (the trailing `SET`/`DEFINED`/
    `BRIEF_DOCS`/`FULL_DOCS` flag-as-kwarg-enum; ~30 lines, only get_property);
  - **function labeled args** (`fun f(~x)`, call `f ~x='v'`) — a real feature
    (yc `fun`→cmake `function()`, needs generated `cmake_parse_arguments`);
    ties to **Y15**.
- **Parked redesigns:**
  - **uniform metaprogramming / raw-escape** story — unify `yc_raw` /
    `ECmakeRaw` / `ECmakeRawCmd` / hybrid `raw_cmake` into one "opaque cmake
    code" model. Now unblocked (the pass is done).
  - **value-default inversion** (bare `foo` = the value) → belongs in **ycn**,
    needs a frequency study ([`var_centric_design.md`](var_centric_design.md)).
  - **dotted globals** (`$cmake.version`) — the corpus falsified "all-caps =
    global"; real namespacing → **ycn** ([`casing_design.md`](casing_design.md)).
- **Latent bugs (matrix-invisible today):**
  - literal-target `${}` **deref** in `set_target_properties` (and install_targets
    target names) — same `EVar→EString` remedy as the property entity fix;
  - **duplicate single-value field → reject** (Y14 pattern, painpoints #11) for
    the record / dotted-label forms.
- **Minor / cosmetic:** specialized getters (`get_source_file_property` /
  `get_test_property` / `get_cmake_property`, mostly covered by generic
  `get_property`) · cache docstring `~doc:` · property cache-semantics test
  (Value vs SET vs DEFINED) · **Y18** first-class object value
  ([`object_value_design.md`](object_value_design.md)).

## Related

- [`surface_status.md`](surface_status.md) — the parser / formatter / LSP
  machinery this design evolves on top of.
- [`casing_design.md`](casing_design.md) — the casing lanes in full.
- [`../worklog/worklog_2026_06.md`](../worklog/worklog_2026_06.md) — the shipped arc.
- [`../cmake/painpoints.md`](../cmake/painpoints.md) — cmake ground-truth (incl. §11).
- [`../yelu_cmake/driver.md`](../yelu_cmake/driver.md) — the
  `text ↔ cst_lite ↔ expr` forms the changes touch.
