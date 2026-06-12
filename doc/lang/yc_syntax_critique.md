# yc surface syntax — critique & improvement plan

> Living doc. Captures where the `.yc` surface reads well, where it reads
> badly, and a per-item plan to tighten it. **Syntax evolution is now a
> safe, mechanical operation:** add sugar / accept a cleaner form in the
> parser, run `yelu fmt -w probes/**/*.yc` to canonicalize, and the
> **emit-bridge** (`test_yc_cst_bridge*`) + the **fmt matrix**
> (`yelu matrix probes/fmt`, 24/24) prove the emitted cmake is unchanged.
> Grounded in `probes/fmt/main.yc` (post-`yelu fmt`).

## What works (keep)

- **Structured control flow** — `if c then ( … ) else ( … )`, `foreach x in … ( … )`,
  `fun f(p) ( … )`. No `endif`/`endforeach`; real nesting. A decisive win
  over cmake.
- **Conditions as expressions** — `if ver_lt ${V} "3.12"`, `if not (defined X)`,
  `a and b or c`. Kills cmake's stringly `if(A AND NOT B)` + implicit-deref
  footguns. The single biggest improvement.
- **`option NAME "help" DEFAULT`** and **`:=`** read cleanly.

## Inelegances (root cause split)

**Self-inflicted (yc's own choices — fixable without losing cmake fidelity):**
1. The `target` tag noise — `compile_opts target fmt …`, `add_lib target fmt …`.
2. Three keyword mechanisms for one concept — `~out:`/`~type:` (tilde),
   bare `COMMAND`/`OUTPUT`/`PROPERTY`/`BEFORE` (UPPER section markers),
   and `:PRIVATE`/`:PUBLIC` (colon-keywords).
3. `'single'` vs `"double"` strings — the path-vs-string type distinction
   (cmake-internal) leaking to the surface; author must track which quote.

**Forced by cmake-faithfulness (harder; sugar only):**
4. `${VAR}` on every read — heavy, but a *deliberate* explicitness win
   (read `${X}` vs name `X`; cmake's auto-deref is the footgun). Defend.
5. `set_target_properties t PROPERTY A … PROPERTY B …` repetition; the
   cache docstring buried as a bare positional (`cache X := v 'doc' ~type:T`).

## Improvement items (one-by-one)

### 1. Implicit target — drop the `target` tag — ✅ **done (2026-06-12)**

`compile_opts target fmt :PRIVATE …` → `compile_opts fmt :PRIVATE …`.

**Shipped.** The coercion lives in the shared `p_target_command_y1_inner`
(both the legacy parser and the CST lowering call it, so they stay
consistent — the lesson the bridge taught: production still compiles via
the legacy parser, so a single-path change isn't enough). The printer omits
the `target` tag for these commands; the corpus was re-`fmt`'d (the tag
vanished from ~30 sites). Verified: emit-bridge green, legacy parser (280)
+ compile-oracle (193) green, **fmt matrix 24/24**. The list lives in
`Yc_cst.target_first_arg_commands`.

**Confirmed (2026-06-12):** the first positional argument is a target for
*every* target-family command **except `add_custom_command`** (which takes
`OUTPUT files`, not a target — it's mis-grouped in the target family). See
`p_target_command_y1_inner`. Commands and their first arg:

- create-a-target: `add_exe`, `add_lib`, `add_lib_alias`, `add_custom_target`
  (the name being created);
- modify-a-target: `link_lib`, `include_dirs`, `compile_defs`,
  `compile_opts`, `compile_feats`, `link_opts`, `link_dirs`,
  `target_sources` (+ `target_*` aliases) — `target :: items`.

**Why safe:** auto-tagging the first positional as a target (in lowering)
emits correctly for both literal and dynamic names —
`compile_opts fmt` → `ETarget "fmt"` → `fmt`; `compile_opts ${tgt}` →
`ETarget "${tgt}"` → `${tgt}` (cmake derefs). The `target` keyword can stay
accepted (back-compat) but `yelu fmt` would drop it.

**Plan:** in `Yc_cst_lower.lower_command`, for the target-family commands
(minus `add_custom_command`), coerce the first positional atom to a target
before calling `_inner`; in the printer, never emit the `target` tag for
those. Re-fmt the corpus; emit-bridge + matrix confirm.

**Exclusion:** `add_custom_command` keeps its `OUTPUT …` form.

Status: **confirmed, not yet implemented.**

### 2. Unify the keyword mechanisms → one form

Pick a single surface for "named modifier" and route the three current
ones through it. Candidate: the `~kw` / `~kw:val` form everywhere, with
`yelu fmt` rewriting bare `BEFORE`/`SYSTEM` flags and `:PUBLIC` visibility
into it (or vice-versa). Needs a design pass: section markers like
`COMMAND`/`OUTPUT` introduce *groups* of args, not single modifiers, so
they may not collapse cleanly into `~kw`. Status: **design needed.**

### 3. Single string syntax → drop `'`/`"`  — **TODO**

> **TODO (deferred).** Unify the two string syntaxes. Design needed before
> implementation.

The `Ycs_path` vs `Ycs_string` distinction is cmake-internal; the author
shouldn't pick quotes. Option: one quote (`"…"`), infer path-ness from
position/command, or make it a non-surface concern. Needs care — the
distinction does affect some emit, so the design pass must map exactly
which emit sites depend on the path-vs-string tag before collapsing it.
Status: **TODO — design needed.**

### 4. `${}` noise — defend; lighten with `$foo` sugar

Keep the *explicit read* — it's correctness, not an accident (and
`EVarLookup` just made it more principled). Two threads came out of the
2026-06-12 discussion:

- **Brace-elision sugar (active candidate).** Accept `$foo` as a lighter
  spelling of `${foo}` for a plain identifier (shell convention). Pure
  surface: the lexer normalizes `$foo` → the same `${foo}` token, so the
  IR / emit are byte-identical (cmake always receives `${foo}`); the
  formatter may print the lighter form for simple names. Braces stay
  required for nested / adjacent-text / in-string cases. Low-risk; reduces
  visual density without touching semantics. Status: **proposed.**
- **Value-default inversion (postponed).** Making bare `foo` = the value
  (name explicit) is a bigger, separate idea — it belongs in *ycn*, not
  yc, and needs a frequency study first. Captured in
  [`var_centric_design.md`](var_centric_design.md). Status: **postponed.**

### 5. Minor — property lists, cache docstring

`set_target_properties` could take a property record; cache could use a
`~doc:` kwarg instead of a bare positional string. Status: **parked.**

### 5. Minor — property lists, cache docstring

`set_target_properties` could take a property record; cache could use a
`~doc:` kwarg instead of a bare positional string. Status: **parked.**

## Related

- [`surface_status.md`](surface_status.md) — the surface track (parser,
  formatter, LSP) this evolves on top of.
- [`../yelu_cmake/driver.md`](../yelu_cmake/driver.md) — the
  text ↔ cst_lite ↔ expr forms the changes touch.
