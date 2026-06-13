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

### 2. Unify the keyword mechanisms → casing lanes + `~` modifiers

The real problem (corpus-grounded): the form is assigned *per-command*, so
the same concept appears in 2–3 forms (output-var as `OUTPUT_VARIABLE` *and*
`~out:`; type as `:STATIC`/`:STRING` *and* `~type:`; mode as `:NAME_WE` *and*
`~mode:NAME_WE`). Fix: surface form = a function of the token's *role*.

**Enum-choice half — designed (2026-06-12), see
[`casing_design.md`](casing_design.md).** Enum choices become leading-cap
constructors (`Public`, no colon); cmake globals become dotted lowercase
(`$cmake.version`); locals stay lowercase; reserved-word shadowing is a hard
reject (Y14). All surface transforms — emit is exact cmake — fmt-canonicalized.

**`~`-modifier half — design settled (2026-06-12), implementation pending.**
A single *labeled-argument* syntax for cmake keyword args (and, later, yc
function labeled params). Marker `~` (explicit > context-sensitive; LLM-
friendly), three forms:

- **flag** — `~before`, `~system`, `~parent_scope` (boolean, present/absent)
- **value** — `~key=value` (`~out=result`, `~type=Static`)
- **group** — `~key=[a, b, c]` (one **comma** list form; `~command=[$cc, '-c',
  $obj]`, Python-`subprocess` style)

Decisions and *why*:
- **`=` not `:`** for the value separator — `:` reads as type ascription
  (`x: T`); `=` reads as binding. The parser already accepts `COLON | EQ`, so
  it's an accept-both, canonicalize-to-`=` migration (`~out:` → `~out=`).
- **one comma list `[a, b, c]`**, *not* a second space-separated form — the
  separator is cosmetic (emit is keyword-driven: `COMMAND`→space args, list
  keyword→`;`-list), so a second form buys no semantics (same reasoning that
  collapsed `'`/`"`); `|…|` was rejected (reads as a shell pipe, worst on the
  command-line case it'd serve). A Ruby/Elixir-style `w[…]` word-sigil is the
  only escape we'd consider, and only if comma proves painful in real use.
- **emit uppercases the key** (`~before` → `BEFORE`; cmake keyword args are
  case-sensitive) — same normalize/canonicalize pattern as the enum slices.
- **`?key=default`** reserved for later *optional-with-default* function
  params — arrives with `cmake_parse_arguments` codegen, not now.

**Function labeled args (later).** Same syntax (`fun f(~variable, ~value)`,
call `f ~variable='X'`), but it's a real feature: yc `fun` → cmake
`function()` (positional + `ARGN`), so labeled params need generated
`cmake_parse_arguments` — which the corpus already hand-rolls
(`cmake_parse_arguments(${AML} …)` in `main.yc`). Ties to **Y15**.

**Slicing.** ① flags → ② single values (`~key=value`, migrate `~out:`/`~type:`
to `=`) → ③ comma-groups (needs the per-keyword arity table: which keyword is
flag / value / group).

**Flags-slice status (2026-06-13).** `~parent_scope` ✅ (shipped) — but it was
the *easy* case: `parent_scope` is a dedicated `bool` field on `S_assign` with
its own parse+print. The remaining flags are **generic command args, and the
clean centralized approach does NOT hold** — commands detect flags
*inconsistently*: `include_guard GLOBAL` / `install … OPTIONAL` detect
**positionally**, target `before`/`system` via **`kw_bool` kwargs** (so
`~before`/`~system`/`~all`/`~force` already work). No uniform `~flag`
normalization exists (positional ⊥ kwarg), and a bare `GLOBAL` is
**context-dependent** (the keyword in `include_guard`, but `${GLOBAL}` (a var)
in a generic/raw command), so the formatter can't canonicalize it
command-agnostically. ⇒ the bare-keyword flags (`GLOBAL`, `OPTIONAL`,
`COMMAND_EXPAND_LISTS`, …) need **per-command, command-aware** accept-`~flag` +
canonicalize work. Status: **per-command pass in progress (not centralizable).**

The per-command mechanism (shipped with `include_guard`):
[`yc_cst_print.ml`](../../src/langs/yelu/yc_cst_print.ml) carries a
`command_flags name → [keyword]` table + `pr_arg_flagged`; the formatter
rewrites a *positional bare keyword* in that command's set to `~flag` (so a
generic `${GLOBAL}` var is untouched). The parser already accepts `~flag`
(arrives as a `Kw_flag` → boolean kwarg). Regression tests live in
`test_yc_cst_bridge` (`test_flags`) — the emit oracle is blind to surface
canonicalization. Per-flag progress:

- ✅ **`~parent_scope`** — the easy case (dedicated `bool` field on `S_assign`).
- ✅ **`include_guard ~global`** (2026-06-13) — first table-driven flag.
- ✅ **`install_directory ~optional`** (2026-06-13) — OPTIONAL is detected
  *positionally*, so the parser also had to learn the `~optional` kwarg (else
  it is silently dropped). Established the pattern for positional flags.
- ✅ **`find_package ~required`** (2026-06-13) — same positional→kwarg fix.
  QUIET/EXACT are not in the find_package IR, so out of scope.

**Stop-and-think finding (2026-06-13): not every flag is IR-modeled.** A
*surface* migration must be emit-byte-invariant, but a cosmetic `~flag` on a
keyword the IR **drops** is *worse* than leaving it bare — it makes a no-op
look first-class. Audited the remaining candidates:

| flag | command | IR models it? | verdict |
| --- | --- | --- | --- |
| `APPEND` | `set_property` | ✅ (3 detect sites + raw-scope fallback) | migratable but fiddly; **not in corpus** |
| `VERBATIM` | `add_custom_command` | ✅ emits | migratable; **not in corpus** |
| `COMMAND_EXPAND_LISTS` | `add_custom_command` | ❌ **dropped on emit** | **do NOT migrate** — IR gap |
| `WIN32` / `MACOSX_BUNDLE` / `EXCLUDE_FROM_ALL` | `add_exe`/`add_lib` | ❌ dropped | **do NOT migrate** — IR gap |

⚠️ **Latent correctness gap (independent of this work):**
`add_custom_command … COMMAND_EXPAND_LISTS` is parsed (consumed by
`split_by_keywords`) but **never stored in `ECmakeAddCustomCommand`**, so emit
silently drops it — the corpus's [main.yc](../../probes/fmt/main.yc) line ~197
`COMMAND_EXPAND_LISTS` is currently a no-op decoration. The matrix can't catch
it (build-time flag, configure-time oracle). Same shape for `WIN32` /
`MACOSX_BUNDLE` / `EXCLUDE_FROM_ALL` on the target-creation commands (the
latter is explicitly accepted-and-dropped, see `yelu_cmake_utils.ml`). Closing
these is an **IR + emit** change (and would change emitted text), not a surface
migration — track separately before migrating those flags.

⏳ **Recommendation:** the clean, IR-faithful per-command flags are done.
`APPEND` / `VERBATIM` are migratable but uncovered (bridge-test only) and lower
value; the dropped-flag group is blocked on the IR gap above. Resume only after
deciding whether to (a) model the dropped flags in the IR first, or (b) migrate
the two uncovered-but-modeled flags as-is.

**Value-labels + nested args — design settled (2026-06-13).** Beyond the
boolean flags, the *value-carrying* cmake keywords (`DESTINATION`, `COMPONENT`,
`EXPORT`, `PROPERTY`, …) are also argument labels → `~key=value`. The argument
shapes (corpus-grounded) and their resolutions:

| shape | example | surface | status |
| --- | --- | --- | --- |
| 1 flat record | `install(DIRECTORY d DESTINATION x COMPONENT c)` | `~destination=x ~component=c` | ✅ install_directory/files/export done; find/file already label-based — corpus shape-1 complete |
| 2 repeated→list | `add_custom_command(… COMMAND a … COMMAND b)` | a list | later |
| 3 key→value map | `set_target_properties(t PROPERTIES K v …)` | `~properties={k=v, …}` | later (record literal) |
| 4 record-list (nested) | `install(TARGETS … LIBRARY DESTINATION d1 ARCHIVE DESTINATION d2)` | **flat dotted label** | see below |

- **Nested (shape 4) → flat dotted labels, tableless.** Artifact-kind is the
  label *prefix*, field the *suffix*, both the cmake name lowercased (no
  abbreviation table — the "tableless to start" stance, [`casing_design.md`](casing_design.md)):
  `~library.destination=$d`, `~archive.destination=$d`,
  `~public_header.destination='…'`; unprefixed = top-level (`~component=`,
  `~export=`). This flattens the record to one level and kills the nested-`()`
  problem. A future record literal (`~library={destination=…, permissions=[…]}`)
  is **parked**.
- **Duplicate single-value field → reject** (Y14 pattern). cmake's real
  behavior is **silent last-wins** for scalar fields and **accumulate** for
  list fields (empirically verified, see [painpoints.md §11](../cmake/painpoints.md)).
  Since yelu emits one record per artifact-kind, a duplicate scalar label is
  always a mistake → error. List fields are written as one list value
  (`~library.permissions=[Owner_read, Owner_write]`), folding cmake's
  cross-appearance merge into a single label. Within-list element dup is a
  separate concern, unchecked for now. Stricter-than-cmake but emit-faithful.
- **`=` not `:` separator**, comma lists — as already settled above.
  Separator migration shipped 2026-06-13 (`:`→`=`, accept-both); the
  `install_directory` value-label pilot (`~destination=`/`~component=`)
  shipped the same day — `command_value_labels` table + `pr_cmd_args`
  (look-ahead printer: a value-keyword consumes its following positional;
  flags are the value-less case). Mechanism is the per-command template;
  order-independence verified (labels in any order → identical cmake).

### 3. Single string syntax — ✅ **done (2026-06-12)**

**Premise corrected.** The doc earlier assumed `'…'` vs `"…"` was a
*path-vs-string type* that "affects some emit". It does not: both lower to
the same `EString` and emit byte-identical cmake (cmake has no char type —
they were never char-vs-string). The only real difference was lexer escape
ergonomics (`"…"` escapes `\"`; `'…'` is raw). So it was pure surface and
safe to canonicalize — no emit sites depend on the tag.

**Shipped.** The formatter ([`yc_cst_print.ml`](../../src/langs/yelu/yc_cst_print.ml)
`pr_string`) canonicalizes both quote forms with the Python / Prettier rule:
**prefer `'…'` (raw, no escaping); fall back to `"…"` (with `\"` / `\\`) only
when the content contains a `'`.** Both forms are still *accepted* on input;
the author no longer tracks which to use. Bonus: backslash-heavy content
(Windows paths, regex) reads cleanly — `'C:\Program Files\…'` instead of
`"C:\\Program Files\\…"`. Corpus re-`fmt`'d to single quotes.

Verified: 655 unit tests, fmt matrix **24/24** (emit unchanged), idempotent.

### 4. `${}` noise — defend; lighten with `$foo` sugar

Keep the *explicit read* — it's correctness, not an accident (and
`EVarLookup` just made it more principled). Two threads came out of the
2026-06-12 discussion:

- **Brace-elision sugar — ✅ done (2026-06-12).** `$foo` is a lighter
  spelling of `${foo}` for a plain identifier (shell convention). The lexer
  ([`yelu_lexer.ml`](../../src/langs/yelu/yelu_lexer.ml) `eval_lit`)
  normalizes `$foo` → the same `${foo}` token, so the IR / emit are
  byte-identical (cmake always receives `${foo}`). The formatter
  ([`yc_cst_print.ml`](../../src/langs/yelu/yc_cst_print.ml)
  `elide_eval_braces` + `pr_name_or`) canonicalizes toward `$foo` in value
  *and* name/target/assignment-LHS slots; braces stay for nested / genex /
  odd-char / **in-string** names (cmake needs `${}` there). Corpus re-`fmt`'d.
  Verified: 655 unit tests (incl. new lexer + elision round-trip tests),
  fmt matrix **24/24**, idempotent.
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
