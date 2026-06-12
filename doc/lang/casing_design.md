# yc identifier casing — enums, variable lanes, reserved names

> **Status: design settled 2026-06-12, implementation deferred behind the
> parser work.** Came out of critique #2 (keyword mechanisms) + the
> `EVarLookup` / `$foo` work. This note covers the *enum-choice* and
> *variable-name* spelling; the `~`-parameter / flag / bracket-group half of
> #2 is still deferred. See [`yc_syntax_critique.md`](yc_syntax_critique.md),
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

## Deferred / open

- **Parser/lexer** (the gate for all of this): a leading-cap token class
  (enum constructors); `.` inside `$`-reads (dotted globals); the verbatim
  escape syntax for oddball names.
- **The `~` half of #2**: flags (`~system`), named values (`~out:`), and
  bracket-groups (`~command:[…]`) — still deferred (groups need a per-keyword
  arity table; that's the real parser work).
- **Namespace prefix table** for dotted-global grouping (start tableless).
- **Full boolean scheme** (fold `ON`/`OFF` or keep) — later.

## Implementation phases (when un-deferred)

1. **Lexer/parser** — leading-cap constructor tokens; `.`-bearing `$`-reads;
   escape form. Validated by the emit-bridge oracle (lower vs parse agree).
2. **Enum table + emit** — per-theory constructor ⇄ cmake-casing table;
   dotted-global emit (`UPPER_SNAKE`); local verbatim. Matrix proves emit
   unchanged.
3. **Formatter canonicalization** — accept cmake-style aliases; rewrite
   `PUBLIC→Public`, `$CMAKE_VERSION→$cmake.version`; transient warnings;
   re-`fmt` the corpus.
4. **Y14 reject** — wellform pass rejecting reserved-word shadowing.

### Progress

- **Slice 1 — visibility constructors ✅ (2026-06-12).** `Public`/`Private`/
  `Interface` (no colon). Same minimal pattern as `$foo`: the lexer
  ([`yelu_lexer.ml`](../../src/langs/yelu/yelu_lexer.ml) `constr_names` /
  `is_known_constr`) promotes a *capitalized* known constructor to the
  uppercased `KEYWORD` token (lowercase `public` stays an IDENT — the
  `~public:` kwarg key); the formatter ([`yc_cst_print.ml`](../../src/langs/yelu/yc_cst_print.ml))
  canonicalizes the recognized `:KEYWORD` back to leading-cap. **Both gate on
  the same `constr_names` set** so the round-trip is consistent — an unmigrated
  enum (e.g. library-type `INTERFACE`) keeps its current form. No
  parser/emit change; corpus re-fmt'd (21 sites); 655 tests, matrix 24/24,
  idempotent. Next slices grow `constr_names` per theory (library/cache type,
  fc mode, …); then dotted globals; then Y14.

Each step follows the proven pattern: accept old forms, `fmt` canonicalizes,
emit-bridge + matrix confirm the emitted cmake is byte-unchanged.
