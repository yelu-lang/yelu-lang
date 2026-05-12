# Retirement Plan (formerly "yelu_tiny → yelu")

The plan for moving production lowering off the legacy
`src/langs/yelu_legacy/` (formerly `src/langs/yelu/fragments/`) and onto
`src/langs/yelu/` (formerly `src/langs/yelu_tiny/`). Companion to
`status.md` (open work) and `design.md` (the *why*).

Note: this doc still lives at `doc/yelu_tiny/` for git-history
continuity; the directory name will be revisited once full E lands.

## Status (2026-05-11)

**Phase 1 + Phase 2a + 2c done; items A, B (reframed), C, D, and
E-utils done. Bridge is off the binary production path.**

**Remaining open:**
- **F** — Parser uses the IR constructor module (refactor; ~10%
  parser LOC; one source of truth for command-shape decisions).
- **G** — Legacy isolation cleanup (move bridge to `yelu_legacy/`;
  extract enum-string converters to `cmake/`; new yelu becomes
  legacy-import-free).
- **E** (deferred to last) — module-level bridge deletion. Gated
  on shifting the byte oracle and pair-wise oracle from bridge-
  fed shape to source-fed shape.

A no-deletion prerequisite ("E-lite") moved the legacy parser
and lexer into `src/langs/yelu_legacy/`. The yelu_tiny directory
has been renamed to `src/langs/yelu/` with all module names
updated. See the rename mapping in item D below.

- Production text generation routes through
  `Yelu1 → emit_ast → Lang_cmake.exp → cmake_pp`.
- Byte-equality oracle in `test_yelu_compile.ml` reports 194/194 programs
  byte-identical with legacy compile.
- `runcmake-yelu` (50 pairs) routes through the AST path; matches
  reference cmake stdout byte-for-byte.
- New parser `Yelu_parse_y1` covers all 12 families. 263 parser tests
  including 93 pair-wise oracle cases agree byte-for-byte with the
  legacy parser → bridge → emit path.
- Legacy compile / wellform / type / utils / 15 fragments relocated from
  `src/langs/yelu/` to `src/langs/yelu_legacy/`. Module names unchanged
  thanks to dune `(include_subdirs unqualified)`; no source-import
  updates required.
- Legacy parser + lexer stay in `src/langs/yelu/` as the still-production
  entry point.
- Two longstanding legacy parser bugs surfaced by the oracle (same
  shape: command that only matches `Yexpr_string` but receives
  `Ycs_path` / `EVar` fallback): `( set NAME val )` and
  `( policy_set "CMPxxxx" )`. Both omitted from oracle; deferred.

## Vocabulary

**Retirement is repointing, not deletion.** The old `yelu_cmake` AST,
compile, wellform, and 15 legacy fragment modules stay on disk after
retirement. What changes is the production call path: it stops going
through `Lang_yelu_compile` and starts going through tiny. The legacy
modules are demoted to `yelu_legacy` — kept callable as a reference
implementation and structural-equivalence oracle.

**Deletion is a separate later decision.** Gated on Y17 (post-retirement
typing pass) plus at least one major version of yelu_tiny shipping
without needing legacy as a cross-check.

## Layering — where each thing sits

`Lang_cmake.exp` is a **CMake syntax AST**, not a semantic theory layer.
Strict downward ordering, semantic richness decreases going down:

```
Yelu2 ideal theories        ← real semantic theories (bool, int, target, …)
        │  lift / lower
Yelu1 CMake-compatible IR   ← cmake-shaped surface; thin semantics
        │  emit_ast (argument erasure happens here)
Lang_cmake.exp syntax AST   ← stringly-typed, mirrors real cmake commands
        │  lang_cmake_pp
CMakeLists.txt              ← text
```

Phase 1's `emit_ast` is a *syntax* translation: Yelu1's typed `expr` shapes
collapse into cmake's `Bare | Quoted | Bracket` arg tokens and
`cond = string list` lists. No semantic checking happens at this layer.
That's why the cmake AST is below Yelu1, not parallel to it.

## End-state goal

```
source.ye  →  parse  →  Yelu1 IR  →  emit_ast  →  Lang_cmake.exp  →  cmake_pp  →  CMakeLists.txt
```

Yelu1 IR is the canonical typed AST. The legacy `Lang_yelu_cmake` AST is
no longer on the production path; it lives in `yelu_legacy/` as the old
reference shape. Emit goes *through* `lang_cmake_pp.ml` (1.4 k lines of
well-tested formatting) rather than re-implementing text rendering —
exactly one cmake pretty-printer in the codebase.

## Where things go

| Module                                                             |   LOC | Today                                   | After retirement                                                                                         |
| ------------------------------------------------------------------ | ----: | --------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `src/langs/yelu/lang_yelu_parse.ml`                                |   955 | concrete syntax → `Lang_yelu_cmake` AST | still production parser; new `Yelu_parse_y1` covers all 12 families in parallel (Phase 2a done)          |
| `src/langs/yelu/lang_yelu_lexer.ml`                                |   197 | tokens                                  | unchanged; shared by both parsers                                                                        |
| `src/langs/yelu_legacy/lang_yelu_cmake.ml` (AST type)              |   348 | production AST type                     | **moved to `yelu_legacy/` (Phase 2c)**; still callable from same library                                 |
| `src/langs/yelu_legacy/lang_yelu_utils.ml`                         |   561 | AST constructors used by step files     | **moved to `yelu_legacy/`**; step files still use it until item C lands                                  |
| `src/langs/yelu_legacy/lang_yelu_compile.ml`                       | 1,125 | production AST → cmake AST              | **moved to `yelu_legacy/`**; off the production text-generation path; serves the byte oracle             |
| `src/langs/yelu_legacy/lang_yelu_wellform.ml`                      |   761 | name binding                            | **moved to `yelu_legacy/`**; Y17 builds tiny's own                                                       |
| `src/langs/yelu_legacy/lang_yelu_type.ml` + `fragments/*_check.ml` |  ~700 | per-theory typecheck                    | **moved to `yelu_legacy/`**; Y17 builds tiny's own                                                       |
| `src/langs/yelu_legacy/fragments/lang_yelu_*.ml` (15)              | ~1.2k | typed constructors + checking functors  | **moved to `yelu_legacy/fragments/`**; not called in production                                          |
| `src/langs/yelu_tiny/yelu_cmake_to_yelu1.ml` (bridge)              | 1,056 | production AST → Yelu1 IR               | stays in `yelu_tiny/`; retires alongside `lang_yelu_cmake` once production callers stop using legacy AST |
| `src/langs/yelu_tiny/yelu_parse_y1.ml`                             | ~1.9k | concrete syntax → Yelu1 IR (Phase 2a)   | new parser; covers all 12 families with byte-identical pair-wise oracle                                  |
| `src/langs/yelu_tiny/yelu_tiny_cmake_emit.ml` (direct text)        |   964 | Yelu1 IR → cmake text                   | **replaced** by `yelu_tiny_cmake_emit_ast.ml` going through cmake AST (Phase 1)                          |
| `src/langs/cmake/lang_cmake.ml` + `lang_cmake_pp.ml` + `_utils.ml` | 2,715 | cmake AST + pp + ctors                  | unchanged — sole canonical text-generation path                                                          |

Note: dune's `(include_subdirs unqualified)` keeps module names the
same after directory relocation, so the Phase 2c move did not require
any source-import updates. Tests, step files, and the bridge all still
reference `Lang_yelu_compile.compile`, `Lang_yelu_cmake.yelu_stmt`,
etc., as before.

## Two phases

**Phase 1 — Emit through cmake AST.** Parser and bridge stay unchanged.
Only the back end of the tiny path moves.

```
before:  parse → yelu_cmake → bridge → Yelu1 → yelu_tiny_cmake_emit       → text
phase 1: parse → yelu_cmake → bridge → Yelu1 → yelu_tiny_cmake_emit_ast  → Lang_cmake.exp → cmake_pp → text
```

**Phase 2 — Parser produces Yelu1 directly.** The yelu_cmake AST and the
bridge both retire. This is where Yelu1 *really* replaces yelu_cmake.

```
phase 2: parse → Yelu1 → yelu_tiny_cmake_emit_ast → Lang_cmake.exp → cmake_pp → text
```

## The hard part of Phase 1: argument erasure

Command-constructor mappings (`ECmakeAddExecutable → Add_executable`, …)
are mechanical — the cmake AST has 352 variants; most Yelu1 cmake-shaped
constructors map 1-to-1. The real work is the *erasure* of Yelu1's typed
expression shape into cmake's flatter token forms.

Four erasures, each gets a dedicated helper in the new emit module:

| Erasure                             | Target type                 | Notes                                                                                                                                                          |
| ----------------------------------- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `expr → Lang_cmake.arg`             | `Bare \| Quoted \| Bracket` | The current `arg : expr → string` helper picks "quoted by default". Choosing `Bare` vs `Quoted` is now structural, not stringified.                            |
| `expr → string` (target / name pos) | plain string                | Target names render unquoted by cmake convention; `target_arg` in the current emit already handles this — port it.                                             |
| `bool expr → Lang_cmake.cond`       | `string list`               | `if(A AND B)` becomes `["A"; "AND"; "B"]`. Parens for nested AND/OR need to be inlined as tokens.                                                              |
| `ELet` substitution                 | (in-emit)                   | Threaded through every arg / cond / target erasure, exactly as `yelu_tiny_cmake_emit.ml` already does via `subst` env. Same logic, different rendering target. |

These four helpers carry essentially all the complexity Phase 1 has to
land. The 1 k lines of command lowering arms below them are mostly
constructor renames.

## Current happy path

After Phase 1, every production yelu program flows through:

```
source.yelu  →  Lang_yelu_parse           (concrete syntax → production AST)
             →  Yelu_cmake_to_yelu1.stmt  (production AST → Yelu1 IR)
             →  Yelu_tiny_cmake_emit_ast  (Yelu1 IR → Lang_cmake.exp)
             →  Lang_cmake_pp.pp          (Lang_cmake.exp → text)
             →  CMakeLists.txt
```

The legacy `Lang_yelu_compile.compile` (production AST →
`Lang_cmake.exp` directly) is still callable and serves as the reference
implementation for the byte-equality oracle. It is not on the production
critical path.

In parallel, `Yelu_parse_y1` reads the same concrete syntax directly
into Yelu1 IR. Pair-wise oracle (`assert_parse_y1_equiv` in
`test_yelu_cmake_parse.ml`) compares legacy parser → bridge → emit vs
new parser → emit at cmake-text level. 93 pair-wise cases pass
byte-identically across all 12 families. The new parser is not yet on
the production switch — item A below covers what closes that gap.

## Running the regression checks

```sh
# Byte-equality oracle: legacy_compile → pp  ≡  bridge → emit_ast → pp
# Runs 194 production-AST programs through both paths and asserts every
# byte matches. The end-of-run stderr line reports:
#   [emit_ast oracle] covered=194  uncovered=0  (194 total)
dune build --force @runtest    # all 831 unit tests, including the oracle
dune test test/test-yelu       # same, scoped to the yelu unit tests

# Runtime equivalence: tiny emit  ≡  reference cmake stdout
# Runs 50 cmake -P script pairs and asserts identical stdout.
make runcmake-yelu

# Direct-text emit regression suite (diagnostic aid coverage)
# Substring-level assertions on the demoted yelu_tiny_cmake_emit path;
# protects against the diagnostic module rotting as new ctors land.
dune test test/test-yelu/test_yelu_tiny_steps.exe
dune test test/test-yelu/test_yelu_tiny_emit.exe
```

Watch the oracle line at the end of `test_yelu_compile`. Any drift from
`covered=194 uncovered=0` is a real regression to investigate.

## Done

Consolidated history; commit refs in parens.

- **Warm-up trio (08a6472).** `Yexpr_is_absolute` real bridge.
  `list(GET)` multi-index. Opaque `ECmakeGenex of string` hook on the
  bridge side so genex strings round-trip without catch-all stubbing.
- **Phase 1 — emit through cmake AST (96062db, 682ebff).** Skeleton
  `yelu_tiny_cmake_emit_ast.ml` lands with the four argument-erasure
  helpers. Production callers (`test_yelu_compile`, `test_runcmake_yelu`)
  routed onto `emit_ast`. Byte-equality oracle covers 194/194 programs
  uncovered=0. `runcmake-yelu` 50/50 pairs identical stdout. Direct-text
  emit demoted to diagnostic aid; step-level tests
  (`test_yelu_tiny_steps`, `test_yelu_tiny_emit`) keep it exercised.
- **Phase 2a — parser produces Yelu1 directly (f12758b → bd455d3).**
  New parser `Yelu_parse_y1` covers all 12 families: control flow
  (let / if / function / macro / while / foreach / apply / break /
  continue / return / cond), var, cmake_op, target, dir, test,
  string, list, file, path, find, install, property. Pair-wise oracle
  `assert_parse_y1_equiv` in `test_yelu_cmake_parse.ml` runs 93 cases
  byte-identical at the cmake-text level.
- **Phase 2c — structural move (894133f).** `src/langs/yelu/`'s
  compile / wellform / type / utils + 15 fragments relocated to
  `src/langs/yelu_legacy/`. dune `(include_subdirs unqualified)` kept
  module names stable, so no source-import updates. Parser + lexer
  remain in `src/langs/yelu/` as the production entry.
- **Item A — direct-parser gap list closed (d6b26e9).** `try_compile`
  / `try_run` added with `t7-try-y1` pair-wise oracle. 27 previously
  legacy-only cases promoted into `t-remaining-y1` pair-wise group
  (parser tests 263 → 291). Four bridge shape gaps explicitly
  deferred — no production caller hits them today (string
  comparison conds beyond equality, `EXCLUDE_FROM_ALL`,
  multi-target `target_link_libraries`,
  `add_custom_command(TARGET ...)`). Legacy-compat defaults in
  `Yelu_parse_y1` documented in the file-level comment. Three legacy
  parser bug shapes (`set NAME val`, `policy_set "CMPxxxx"`,
  `cmake_call "myfn"`) omitted from oracle with explanatory
  comments; legacy fix deferred.
- **Item B — genex (reframed).** The production switch does not need
  first-class typed genex ctors; both legacy and tiny carry generator
  expressions as opaque strings end-to-end. Added `t9-genex-y1`
  pair-wise oracle group (5 cases, 4 byte-identical, 1 deferred as
  the fourth legacy `Ycs_eval` bug-shape on `message`). Direct
  parser now also handles `~public:[items]` / `~private:[...]` /
  `~interface:[...]` kwarg-lists by consuming-and-discarding items
  (matches legacy semantics). Typed genex theory deferred to Y17.
- **Item C — binary callers repointed.** Step files in
  `src/bin/yelu/v1/`, `src/bin/yelu/v2/`, and `src/bin/yelu/`
  (CMakeOnly suite) all funnel through one helper —
  `Step_common.print_cmake` — which was the sole call site of
  `Lang_yelu_compile.compile` in the binary tree. Repointed it onto
  `Yelu_cmake_legacy_bridge.stmt |> Yelu_cmake_surface_emit.emit_ast`,
  preserving the same `Lang_cmake_pp` rendering. Verified via
  `make cmake-only-check` (12/12 OK) and `make runcmake-yelu`
  (50/50). The legacy compile stays callable for the byte-equality
  oracle in `test_yelu_compile.ml`. (`make cmake-commands` has a
  pre-existing failure since the initial commit unrelated to the
  retirement work: `yis_target` expects `Yexpr_name` but
  `test_cmake_commands.ml:1560` passes `ystr "Another::Alias"`.)
- **E-lite — legacy parser/lexer relocated.** `git mv` moved
  `lang_yelu_parse.ml` and `lang_yelu_lexer.ml` from
  `src/langs/yelu/` into `src/langs/yelu_legacy/`. dune
  `(include_subdirs unqualified)` kept the module names stable, so
  no import edits were needed. This emptied `src/langs/yelu/`,
  unblocking item D's directory rename.
- **Item D — naming honesty rename.** `src/langs/yelu_tiny/` renamed
  to `src/langs/yelu/`. File and module renames:
    - `yelu_tiny.ml` → `yelu_cmake_ir.ml` (core IR types/env/eval)
    - `yelu_parse_y1.ml` → `yelu_parse.ml`
    - `yelu_cmake_to_yelu1.ml` → `yelu_cmake_legacy_bridge.ml`
    - `yelu_tiny_cmake_emit_ast.ml` → `yelu_cmake_surface_emit.ml`
    - `yelu_tiny_cmake_emit.ml` → `yelu_cmake_surface_emit_debug.ml`
    - `yelu_tiny_yelu1.ml` → `yelu_cmake_surface_eval.ml`
    - `yelu_tiny_yelu2.ml` → `yelu_cmake_eval.ml`
    - `yelu_tiny_translate.ml` → `yelu_cmake_translate.ml`

  Test files dropped the `_tiny` infix
  (`test_yelu_tiny_*` → `test_yelu_*`); helper renamed
  `yelu_tiny_test_helpers.ml` → `yelu_test_helpers.ml`. Module
  references updated across ~50 files in one mechanical token
  pass (superstring-first order, verified by build). Tests stay
  byte-identical: byte-equality oracle 194/194; parser 295;
  `make cmake-only-check` 12/12; `make runcmake-yelu` 50/50.
- **E-utils — step files emit Yelu1 IR directly (aa9c703).** New
  module `src/langs/yelu/yelu_cmake_ir_utils.ml` mirrors
  `Lang_yelu_utils` but returns `Yelu_cmake_ir.expr` instead of
  legacy AST. Parallel `src/bin/yelu/common/step_common_ir.ml` is
  the IR-typed twin of `Step_common`. All ~50 step files in
  `src/bin/yelu/` swapped their `open` from `Lang_yelu_utils` /
  `Step_common` to `Yelu_cmake_ir_utils` / `Step_common_ir`;
  `step_common` library is now `(wrapped false)` so both
  `Step_common` (legacy, for tests on the bridge side) and
  `Step_common_ir` (IR, for binaries) are visible. Verified
  byte-identical: `make cmake-only-check` 12/12,
  `make runcmake-yelu` 50/50, byte oracle 194/194, parser 295.

  **What "bridge off the binary path" means:** at runtime, when a
  step binary emits cmake text, no `Yelu_cmake_legacy_bridge.*`
  function is called. The chain is
  `step file → Yelu_cmake_ir_utils → Yelu_cmake_ir.expr →
  Yelu_cmake_surface_emit.emit_ast → Lang_cmake.exp → cmake_pp →
  text`. The bridge module is still on disk and still imported
  (the new utils call its `string_of_message_mode` etc. to avoid
  duplicating enum-string conversion), but no production text-
  generation flow passes through `Yelu_cmake_legacy_bridge.stmt`.
  The bridge module remains callable by the byte oracle in
  `test_yelu_compile.ml` and the legacy side of the pair-wise
  oracle in `test_yelu_cmake_parse.ml`.

## Open

### F — Parser uses the IR constructor module

The current parser (`Yelu_parse`) dispatches each command and
builds the IR ctor inline — duplicating the same shape decisions
that now live in `Yelu_cmake_ir_utils`. The value-list
normalization in `yc_set` (`[] / [v] / vs` cases), the visibility-
group folding in `include_dirs` / `compile_defs` / etc., the
`Ylet → ELet` body-folding in `ycmd_of_list`, and the
enum-to-string conversion for `message` mode — all repeated.

Refactoring the parser dispatchers to call the constructor module
would:

- collapse ~200 lines of repeated case logic;
- give the project **one** source of truth for "what does this
  command shape become in IR" — fix a default once, both step
  files and the parser get it;
- naturally compose with future fragment-level cleanups
  (item #3 in `status.md` — moving emit/translate arms closer to
  each fragment).

Estimated parser shrinkage: ~10% LOC, but the structural win
matters more than the line count.

**Sequencing:** kept as a separate item from retirement so we can
audit and decide on future optimization (laziness, sharing,
tagless-final-like derivation) before landing it on the parser.
Orthogonal to E; can land any time after E-utils.

### G — Legacy isolation cleanup

**Current state, on disk:**
- `src/langs/yelu/yelu_cmake_legacy_bridge.ml` sits inside the
  *new* yelu directory but is semantically a legacy adapter — it
  converts `Lang_yelu_cmake` AST to Yelu1 IR. The new yelu
  shouldn't logically know it exists.
- `yelu_cmake_ir_utils.ml` calls `Yelu_cmake_legacy_bridge.string_of_*`
  (purely cmake enum→string helpers, not legacy-specific).

**End state — "new yelu ignorable about legacy":**
- `src/langs/yelu/`     ← new yelu only (parser, IR, ctors, emit,
                          eval, translate). No `Lang_yelu_*`
                          imports. No legacy bridge.
- `src/langs/yelu_legacy/` ← legacy yelu **plus** the bridge.
                          The bridge naturally belongs here since
                          it adapts legacy → new; the *new* code
                          shouldn't import from it.
- `src/langs/cmake/`    ← extract the enum-to-string converters
                          (`string_of_message_mode`,
                          `string_of_version`,
                          `string_of_supported_lang`,
                          `string_of_compatibility`) here, where
                          they belong — they only depend on
                          `Lang_cmake`. Both the bridge and the
                          IR ctors then import them from the cmake
                          layer.

**Concrete moves:**
1. Create `src/langs/cmake/lang_cmake_strings.ml` with the four
   enum→string helpers (lifted out of `Yelu_cmake_legacy_bridge`).
2. `git mv src/langs/yelu/yelu_cmake_legacy_bridge.ml
   src/langs/yelu_legacy/`. Update the bridge to import enum
   helpers from `Lang_cmake_strings`. Tests that already use
   `Yelu_cmake_legacy_bridge.stmt` keep working — module name
   unchanged (dune `include_subdirs unqualified`).
3. Update `yelu_cmake_ir_utils.ml` to call `Lang_cmake_strings.*`
   instead of `Yelu_cmake_legacy_bridge.string_of_*`.
4. Verify `src/langs/yelu/` no longer imports any `Lang_yelu_*` or
   `Yelu_cmake_legacy_bridge` module.
5. **Drop the `_ir` infix.** The `IR` label undermined the selling
   point — `yelu_cmake` *is* the language, not an "intermediate"
   thing on the way to something else. Rename:
   - `yelu_cmake_ir.ml` → `yelu_cmake.ml`
     (module `Yelu_cmake_ir` → `Yelu_cmake`)
   - `yelu_cmake_ir_utils.ml` → `yelu_cmake_utils.ml`
     (module `Yelu_cmake_ir_utils` → `Yelu_cmake_utils`; matches
     the cmake layer's `Lang_cmake_utils` naming pattern)

   Touches ~50 import sites; same superstring-first sed pass as
   item D used. Tests must stay byte-identical.

After G, the dependency rule "new yelu does not know about legacy"
is enforced at the import level. Bridge-testing
(`test_yelu_compile.ml`'s byte oracle and the pair-wise oracle)
still works — those tests import both new yelu *and* legacy,
which is appropriate for tests.

### E — Bridge retirement

After items A, B (reframed), C, E-lite, D, and E-utils, the bridge
(`Yelu_cmake_legacy_bridge`, formerly `Yelu_cmake_to_yelu1`) is
**off the binary production path** but still has consumers:

1. **The byte oracle in `test_yelu_compile.ml`** — feeds programs
   constructed as legacy AST through both `legacy_compile → pp`
   and `bridge → emit_ast → pp`, asserting byte equality.
2. **The pair-wise oracle in `test_yelu_cmake_parse.ml`** — the
   legacy side of the comparison uses `Lang_yelu_parse → bridge →
   emit_ast`.

Both are test infrastructure; neither is on a binary path. Full
module-level deletion would require shifting both oracles from
the bridge-fed shape to a source-fed shape:

```
legacy_text = source |> Lang_yelu_parse.parse |> Lang_yelu_compile.compile |> pp
new_text    = source |> Yelu_parse.parse      |> Yelu_cmake_surface_emit.emit_ast |> pp
assert byte-identical
```

That's separable from retirement (the production critical-path
retirement is already done after E-utils). Defer; revisit after
item G makes the layering crisp.

Once either lands, the bridge can be deleted and the
byte-equality oracle in `test_yelu_compile.ml` shifts from the
bridge-fed shape (legacy AST in, two paths out) to the source-fed
shape (source in, two parsers + two emits, same `Lang_cmake_pp`).
`Lang_yelu_cmake` (the AST type) may then stay in `yelu_legacy/`
as a frozen reference shape, callable only by the legacy compile.

**Phase 2 done criterion:** production path is
`parse → Yelu1 → emit_ast → cmake_pp → text` with no
`yelu_legacy` imports on the binary side. Legacy compile stays
callable for the oracle test.

## Equivalence oracle (kept callable forever)

The legacy `Lang_yelu_compile.compile` function is the **reference
implementation**. Two oracle shapes, depending on phase:

**Today (Phase 1 done, parser switch pending):**

```ocaml
let oracle (prog : Lang_yelu_cmake.yelu_stmt list) =
  let legacy_text  = prog |> Lang_yelu_compile.compile  |> Lang_cmake_pp.pp_to_string in
  let tiny_text    = prog |> Yelu_cmake_to_yelu1.stmt    |> Yelu_tiny_cmake_emit.emit_ast |> Lang_cmake_pp.pp_to_string in
  Alcotest.(check string) "legacy AST → text == tiny AST → text" legacy_text tiny_text
```

**After E (bridge retired):**

```ocaml
let oracle (source : string) =
  let legacy_text =
    source |> Legacy_parse.parse |> Lang_yelu_compile.compile  |> Lang_cmake_pp.pp_to_string in
  let tiny_text =
    source |> Parse.parse        |> Yelu_tiny_cmake_emit.emit_ast |> Lang_cmake_pp.pp_to_string in
  Alcotest.(check string) "legacy source → text == tiny source → text" legacy_text tiny_text
```

The shift is which parser feeds each side — but both sides always end
at `Lang_cmake_pp.pp_to_string` against the same cmake AST, so the
equivalence claim stays byte-level.

## What stays callable forever (until separate decision)

- `yelu_legacy.Lang_yelu_compile` — the oracle.
- `yelu_legacy.Lang_yelu_wellform` — Y17 comparison baseline.
- `yelu_legacy.lang_yelu_type` + `fragments/*_check.ml` — same.

## What never gets deleted (without separate decision)

- The `yelu_legacy/` directory in its entirety. Even after Y17 lands a
  better checker, keep legacy until at least one major version of yelu
  has shipped without needing the cross-check.

## Sequencing summary

```
done:       warm-up trio  →  Phase 1 (emit_ast)  →  Phase 2a (parser-direct-to-Yelu1, 12 families)  →  Phase 2c (legacy fragments relocated)  →  A (direct-parser gap list closed)  →  B (genex opaque-string sufficient; typed theory → Y17)  →  C (binary callers onto bridge + emit_ast)  →  E-lite (legacy parser+lexer to yelu_legacy)  →  D (yelu_tiny renamed to yelu)  →  E-utils (step files emit IR directly; bridge off binary path)
open F:     parser-uses-IR-ctors refactor (one source of truth for command-shape decisions; ~10% parser LOC; orthogonal — audit before landing)
open G:     legacy isolation cleanup (move bridge to yelu_legacy/; extract enum-string converters to cmake/; new yelu becomes legacy-import-free)
open E:     module-level bridge deletion — shift byte oracle and pair-wise oracle to source-fed shape; then delete yelu_cmake_legacy_bridge.ml
y17:        post-retirement typing pass on the renamed harness (incl. typed genex)
delete?:    separate decision, gated on Y17 + production stability
```

Each transition is PR-sized. The work that remains is mostly *moving*
code rather than rewriting it.
