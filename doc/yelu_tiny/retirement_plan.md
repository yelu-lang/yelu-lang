# yelu_tiny — Retirement Plan

The plan for moving production lowering off the legacy
`src/langs/yelu_legacy/` (formerly `src/langs/yelu/fragments/`) and onto
`src/langs/yelu_tiny/`. Companion to `status.md` (open work) and
`design.md` (the *why*).

## Status (2026-05-11)

**Phase 1 done; Phase 2a + 2c structural move done; items A and B
(reframed) done; items C–E open.**

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

| Module                                                | LOC   | Today                                  | After retirement                                                                  |
| ----------------------------------------------------- | ----: | -------------------------------------- | --------------------------------------------------------------------------------- |
| `src/langs/yelu/lang_yelu_parse.ml`                   |   955 | concrete syntax → `Lang_yelu_cmake` AST | still production parser; new `Yelu_parse_y1` covers all 12 families in parallel (Phase 2a done) |
| `src/langs/yelu/lang_yelu_lexer.ml`                   |   197 | tokens                                 | unchanged; shared by both parsers                                                 |
| `src/langs/yelu_legacy/lang_yelu_cmake.ml` (AST type) |   348 | production AST type                    | **moved to `yelu_legacy/` (Phase 2c)**; still callable from same library          |
| `src/langs/yelu_legacy/lang_yelu_utils.ml`            |   561 | AST constructors used by step files    | **moved to `yelu_legacy/`**; step files still use it until item C lands           |
| `src/langs/yelu_legacy/lang_yelu_compile.ml`          | 1,125 | production AST → cmake AST             | **moved to `yelu_legacy/`**; off the production text-generation path; serves the byte oracle |
| `src/langs/yelu_legacy/lang_yelu_wellform.ml`         |   761 | name binding                           | **moved to `yelu_legacy/`**; Y17 builds tiny's own                                |
| `src/langs/yelu_legacy/lang_yelu_type.ml` + `fragments/*_check.ml` | ~700 | per-theory typecheck             | **moved to `yelu_legacy/`**; Y17 builds tiny's own                                |
| `src/langs/yelu_legacy/fragments/lang_yelu_*.ml` (15) | ~1.2k | typed constructors + checking functors | **moved to `yelu_legacy/fragments/`**; not called in production                   |
| `src/langs/yelu_tiny/yelu_cmake_to_yelu1.ml` (bridge) | 1,056 | production AST → Yelu1 IR              | stays in `yelu_tiny/`; retires alongside `lang_yelu_cmake` once production callers stop using legacy AST |
| `src/langs/yelu_tiny/yelu_parse_y1.ml`                | ~1.9k | concrete syntax → Yelu1 IR (Phase 2a)  | new parser; covers all 12 families with byte-identical pair-wise oracle           |
| `src/langs/yelu_tiny/yelu_tiny_cmake_emit.ml` (direct text) | 964 | Yelu1 IR → cmake text             | **replaced** by `yelu_tiny_cmake_emit_ast.ml` going through cmake AST (Phase 1)   |
| `src/langs/cmake/lang_cmake.ml` + `lang_cmake_pp.ml` + `_utils.ml` | 2,715 | cmake AST + pp + ctors          | unchanged — sole canonical text-generation path                                   |

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

| Erasure                              | Target type              | Notes                                                                                                                            |
| ------------------------------------ | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `expr → Lang_cmake.arg`              | `Bare \| Quoted \| Bracket` | The current `arg : expr → string` helper picks "quoted by default". Choosing `Bare` vs `Quoted` is now structural, not stringified. |
| `expr → string` (target / name pos)  | plain string             | Target names render unquoted by cmake convention; `target_arg` in the current emit already handles this — port it.                |
| `bool expr → Lang_cmake.cond`        | `string list`            | `if(A AND B)` becomes `["A"; "AND"; "B"]`. Parens for nested AND/OR need to be inlined as tokens.                                 |
| `ELet` substitution                  | (in-emit)                | Threaded through every arg / cond / target erasure, exactly as `yelu_tiny_cmake_emit.ml` already does via `subst` env. Same logic, different rendering target. |

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

## Open

Letter scheme so future additions don't disturb existing numbering.

### C — Repoint binary callers

Step files in `src/bin/yelu/v1/`, `src/bin/yelu/v2/`, and
`src/bin/yelu/` (CMakeOnly suite) currently build production AST via
`Lang_yelu_utils` and route through `Lang_yelu_compile.compile`. Move
them onto the direct path: either build Yelu1 directly with tiny
constructors, or keep producing `Lang_yelu_cmake` AST but route through
`Yelu_cmake_to_yelu1.stmt |> emit_ast`. C must land before E (deleting
the bridge) and before D's rename (so the rename doesn't touch step
files mid-migration).

### D — Naming honesty rename

`yelu_tiny` was a useful experiment name, but it is no longer tiny and
should disappear once the direct parser is the production path. Use
language-level names, not `IR` / `DSL` labels:

- `yelu_cmake_surface` — current Yelu1: CMake-faithful surface
  language, command-shaped, used for byte parity and exact emission.
- `yelu_cmake` — current Yelu2: the improved Yelu CMake language,
  still in the CMake/build domain but not forced to mirror CMake's
  statement/output-variable shape.
- `yelu_cmake_legacy` — old `Lang_yelu_cmake` AST / compiler stack,
  retained as oracle and Y17 reference.

A final move merges `src/langs/yelu_tiny/` into `src/langs/yelu/`,
joining the parser/lexer already there:

- `yelu_parse_y1.ml` → `yelu_parse.ml`
- `yelu_tiny_cmake_emit_ast.ml` → `yelu_cmake_surface_emit.ml`
- `yelu_tiny_cmake_emit.ml` → `yelu_cmake_surface_emit_debug.ml`
- `yelu_tiny_yelu1.ml` → `yelu_cmake_surface_eval.ml`
- `yelu_tiny_yelu2.ml` → `yelu_cmake_eval.ml`
- `yelu_tiny_translate.ml` → `yelu_cmake_translate.ml`
- `yelu_cmake_to_yelu1.ml` → `yelu_cmake_legacy_bridge.ml` (until E
  deletes it).

### E — Bridge retirement

Once A is closed and C has moved every production caller onto the
direct parser, the bridge has no inputs left.

- Move `lang_yelu_cmake.ml` (the AST type) into `yelu_legacy/` —
  parser no longer produces it.
- Delete `yelu_cmake_to_yelu1.ml`.
- Switch the byte-equality oracle in `test_yelu_compile.ml` from the
  bridge-fed shape (legacy AST in, two paths out) to the source-fed
  shape (source in, two parsers + two emits, same `Lang_cmake_pp`).

**Phase 2 done criterion:** production path is
`parse → Yelu1 → emit_ast → cmake_pp → text` with no `yelu_legacy`
imports. Legacy compile stays callable for the oracle test.

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
done:       warm-up trio  →  Phase 1 (emit_ast)  →  Phase 2a (Yelu_parse_y1, 12 families)  →  Phase 2c (legacy move)  →  A (direct-parser gap list closed)  →  B (genex opaque-string handling sufficient; typed theory deferred to Y17)
open C:     repoint binary callers in src/bin/yelu/* off Lang_yelu_compile
open D:     naming honesty rename — yelu_tiny → yelu, naming aligned with surface vs cmake vs legacy
open E:     bridge retirement — delete yelu_cmake_to_yelu1.ml; oracle shifts to source-fed shape
y17:        post-retirement typing pass on tiny (incl. typed genex)
delete?:    separate decision, gated on Y17 + production stability
```

Each transition is PR-sized. The work that remains is mostly *moving*
code rather than rewriting it.
