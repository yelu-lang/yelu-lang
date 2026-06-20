# yc identifier casing — enums, variable lanes, reserved names

> **Status: the enum-casing lanes shipped** (visibility / type / mode / language
> constructors + property scopes + Y14 reject) as part of the no-ALL_CAPS pass —
> arc in [worklog 2026-06](../worklog/worklog_2026_06.md); the `~`-half of
> critique #2 it sat next to is **complete**. This doc keeps the durable
> *design rationale* (casing-shape-tells-kind, the three variable lanes, Y14)
> and the **remaining open lanes** (§ Status & open below). Came out of
> critique #2 + the `EVarLookup` / `$foo` work. See
> [`yc_syntax_critique.md`](yc_syntax_critique.md),
> [`../cmake/var_reference_semantics.md`](../cmake/var_reference_semantics.md).

## The idea: casing *shape* tells you the kind

Today yc spells the same concept three ways depending on the command
(`:STATIC` vs `~type:STATIC`; `OUTPUT_VARIABLE` vs `~out:`). The fix is to make
the surface *shape* a function of the token's kind, uniformly:

| surface shape | kind | emits as |
| --- | --- | --- |
| `Public`, `Name_we` | **enum constructor** (closed-set choice) | table → `PUBLIC` / `NAME_WE` |
| `$cmake.version` | **namespaced cmake global** (builtin / cache / option) | uppercase each segment, join `_` → `CMAKE_VERSION` |
| `$result`, `$my_var` | **local variable** | verbatim → `result` |

Reads are always sigiled (`$…`), so a bare `Public` is unambiguously an enum,
never a variable. The **dot** discriminates global from local. All three are
*surface* transforms — emit is exact cmake (faithfulness preserved where it
counts; explicitness where it helps; calmer, less SHOUTY surface; one casing
rule a model can learn instead of memorizing cmake's spellings).

## Enum constructors — leading-cap, no colon

Closed-set choices (visibility `Public/Private/Interface`, library type
`Static/Shared`, cache type `String/Bool/Path`, fc mode `Name_we`, version
compat `Any_newer_version`, …) are **leading-capital, snake-rest** — the
ML/Rust variant-constructor convention. The capital self-marks, so the old
`:` sigil is **dropped**: `compile_opts fmt :PRIVATE $flags` →
`compile_opts fmt Private $flags`.

- This makes the surface echo the IR's algebra (`Public` ↔ `Vis_public`); the
  cmake AST already models explicit defaults like `Default_order`.
- **Emit is table-driven** (closed set), so it maps *any* cmake casing — both
  ALL_CAPS (`PUBLIC`) and CamelCase (`AnyNewerVersion ⇄ Any_newer_version`).
- **`Default`** models a default as an explicit, *elidable* case (the
  formatter may omit it in the default position) rather than a magic absent
  token — honest and AI-legible.
- **Booleans** (`On/Off/True/False`) are a 2-value enum. For now **accept
  `On`/`Off`**; whether to fold cmake's `ON`/`OFF` fully is a later issue.

## Variable names — three lanes

- **local** — lowercase, underscores preserved: `$result`, `$my_var` →
  `result`, `my_var` (verbatim).
- **cmake global** — dotted lowercase: `$cmake.version`,
  `$cmake.cxx.standard`, `$project.source.dir`. Emit = **uppercase each
  segment, join with `_`** → `CMAKE_VERSION`, `CMAKE_CXX_STANDARD`,
  `PROJECT_SOURCE_DIR`. Fully syntactic and invertible — **no table** (cmake
  globals are all-caps, so the round-trip is exact). The dot is the only
  marker; locals never get dotted.
  - **Tableless to start** — accept the over-segmentation
    (`CMAKE_CXX_STANDARD → cmake.cxx.standard`, treating every `_` as a level
    rather than namespace + member). A prefix table (`CMAKE`/`PROJECT`/lang/
    project-name) for `cmake.cxx_standard`-style grouping is a *later* option,
    only if the over-segmentation grates.
- **oddballs** — a genuinely mixed-case var (`MyVar`, legal cmake) or one with
  a literal `.` can't ride either rule (case-sensitive emit would corrupt it).
  These use a **verbatim escape** (syntax TBD with the parser). Builtins are
  all-caps so they're unaffected; this only bites the rare hand-rolled name.

**Why emit must be exact:** cmake variable names are **case-sensitive**
(`${FOO} ≠ ${foo}`). So the surface↔emit maps above are not cosmetic — getting
them wrong silently references a different variable. The leading-cap →
uppercase and dotted → `UPPER_SNAKE` rules are chosen precisely because they're
*total and invertible* for the cmake conventions they target.

## Reserved-word shadowing — hard reject (Y14)

A variable **declaration** whose name matches a known enum constructor or
cmake keyword → **error** (not warning), with a rename hint. **Case-
insensitive** (`PUBLIC` / `Public` / `public` as a var name all blocked),
**declarations only** (reads are sigiled, never ambiguous). The reserved set
is small and closed and such a collision is always a mistake, so rejecting
keeps the lanes crisp. This is the concrete trigger set for TODO item **Y14**.

(Note: do *not* blanket-warn on ALL_CAPS variable names — cmake's `CMAKE_*` /
cache convention is legitimate and everywhere; those become dotted globals,
not errors.)

## Input forgiveness + fmt canonicalization

Same accept-both-then-canonicalize pattern as quotes and `$foo`: **accept**
cmake-style spellings on input — full-caps enum `PUBLIC`, all-caps global
`$CMAKE_VERSION` — and **`fmt` canonicalizes** them to the yc form (`Public`,
`$cmake.version`), with a **transient warning** that disappears after the
first format pass. A cmake-trained user or model is auto-corrected, not
errored (except the Y14 reserved-word collision, which is a real mistake).

## Status & open

**Shipped** (no-ALL_CAPS pass; full detail in
[worklog 2026-06](../worklog/worklog_2026_06.md)):

- **Enum constructors** — visibility (`Public`/`Private`/`Interface`),
  type/mode/language (`Static`/`String`/`Name_we`/`Cxx`), property scopes
  (`Global`/`Cache`/`Source`/`Test`/`Install`/`Directory`/`Variable`) and
  get_property modes (`Set`/`Defined`/…). The lexer
  ([`yelu_lexer.ml`](../../src/langs/yelu/yelu_lexer.ml) `constr_names` /
  `is_known_constr`) promotes a *capitalized* known constructor to the
  uppercased `KEYWORD` token; the formatter
  ([`yc_cst_print.ml`](../../src/langs/yelu/yc_cst_print.ml)) canonicalizes back
  to leading-cap. Both gate on the same set, so the round-trip is consistent;
  emit byte-unchanged. (All shipped enums are all-caps in cmake, so tableless.)
- **Y14 reserved-word reject** — a var / cache / option / let *declaration*
  shadowing a known constructor (case-insensitive) is a **fatal** compile error
  (`Yc_wellform.check_enum_shadow` → `Enum_shadow`; capitalized `set Public` is
  already a *parse* error). Escape hatch (downgrade to warning / toolset toggle)
  if it proves too aggressive — kept hard for now.

**Open lanes:**

- **Dotted globals** (`$cmake.version` → `CMAKE_VERSION`) — **parked → ycn.** The
  corpus killed the "all-caps = global" premise (`$ARGN`/`$BMI`/`$MKDOCS` are
  *local* all-caps), so the dotted form is only cosmetic and real namespacing
  belongs in ycn. Needs `.` inside `$`-reads; the namespace prefix table
  (CMAKE/PROJECT/lang grouping) rides with it.
- **CamelCase compat enums** (`AnyNewerVersion ⇄ Any_newer_version`) — need the
  per-theory constructor⇄cmake-casing **table** (uppercase ≠ cmake casing),
  unlike the all-caps ones that shipped tableless.
- **Oddball verbatim escape** — a genuinely mixed-case var (`MyVar`) or one with
  a literal `.` can't ride the lanes (case-sensitive emit would corrupt it);
  needs an escape syntax (TBD). Rare — builtins are all-caps.
- **Full boolean scheme** — fold cmake's `ON`/`OFF` into the `On`/`Off` enum, or
  keep both. Later.
