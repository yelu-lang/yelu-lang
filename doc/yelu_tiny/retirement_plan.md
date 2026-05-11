# yelu_tiny — Retirement Plan

The plan for moving the production lowering off `src/langs/yelu/fragments/`
and onto `src/langs/yelu_tiny/`. Companion to `status.md` (open work) and
`design.md` (the *why*). Status as of 2026-05-11: planning, not started.

## Vocabulary

**Retirement is repointing, not deletion.** The old `yelu_cmake` AST,
compile, wellform, and 14 `Make_*` fragments stay on disk after
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
well-tested formatting) rather than re-implementing text rendering — exactly
one cmake pretty-printer in the codebase.

## Where things go

| Module                                                | LOC   | Today                                  | After retirement                                                                  |
| ----------------------------------------------------- | ----: | -------------------------------------- | --------------------------------------------------------------------------------- |
| `lang_yelu_parse.ml`                                  |   955 | concrete syntax → `Lang_yelu_cmake` AST | **refactored** to produce Yelu1 IR directly (Phase 2). Reuses lexer.              |
| `lang_yelu_lexer.ml`                                  |   197 | tokens                                 | unchanged                                                                         |
| `lang_yelu_cmake.ml` (AST type)                       |   348 | production AST type                    | moved to `yelu_legacy` once parser no longer targets it                           |
| `lang_yelu_utils.ml`                                  |   561 | AST constructors used by step files    | moved to `yelu_legacy`; step files migrate to Yelu1 constructors                  |
| `lang_yelu_compile.ml`                                | 1,125 | production AST → cmake AST             | moved to `yelu_legacy.compile`; off the production path, kept as oracle           |
| `lang_yelu_wellform.ml`                               |   761 | name binding                           | moved to `yelu_legacy.wellform`; Y17 builds tiny's own                            |
| `lang_yelu_type.ml` + `fragments/*_check.ml`          |  ~700 | per-theory typecheck                   | moved to `yelu_legacy`; Y17 builds tiny's own                                     |
| `fragments/lang_yelu_*.ml` (14 `Make_*_op`)           | ~1.2k | typed constructors + checking functors | moved to `yelu_legacy`; not called in production                                  |
| `yelu_cmake_to_yelu1.ml` (bridge)                     | 1,056 | production AST → Yelu1 IR              | retires alongside `lang_yelu_cmake` (Phase 2)                                     |
| `yelu_tiny_cmake_emit.ml` (direct text)               |   964 | Yelu1 IR → cmake text                  | **replaced** by `yelu_tiny_cmake_emit_ast.ml` going through cmake AST (Phase 1)   |
| `lang_cmake.ml` + `lang_cmake_pp.ml` + `_utils.ml`    | 2,715 | cmake AST + pp + ctors                 | unchanged — sole canonical text-generation path                                   |

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

### Genex during Phase 1

First-class genex (`R3`) is **required for full retirement**, but Phase 1
does **not** require it landed first. The current bridge already passes
generator expressions through as opaque `EString` values (from
`Ycs_eval`). Phase 1 preserves that: opaque genex strings render as
`Lang_cmake.Quoted` or `Bare` tokens depending on context, exactly as the
direct-text emit does today. R3 stays a Phase 2 / post-retirement work
item.

## Concrete steps

### Pre-Phase-1 warm-up

1. **`Yexpr_is_absolute` real bridge.** Currently `EBool false` at
   `yelu_cmake_to_yelu1.ml:59`. Small.
2. **`list(GET)` multi-index.** Bridge fails on >1 index at
   `yelu_cmake_to_yelu1.ml:223`. Small.

(R3 genex is no longer a Phase 1 prerequisite.)

### Phase 1 — Emit through cmake AST

3. **Skeleton `yelu_tiny_cmake_emit_ast.ml`.** Mirrors
   `yelu_tiny_cmake_emit.ml`'s match structure but produces
   `Lang_cmake.exp` values. Start with the four erasure helpers above.
4. **Wire alt entry point.** Add `emit_ast :: expr → Lang_cmake.exp`
   alongside the existing `emit_script :: expr → string`. Both stay
   callable.
5. **Parity tests.** Every emit test gets a companion: pipe through
   `emit_ast |> lang_cmake_pp.pp_to_string` and assert against the
   direct-text baseline. Where they diverge, pick the cmake_pp output as
   canonical and update the baseline. The direct-emit module is the one
   being retired; its formatting choices don't win.
6. **Repoint runcmake-yelu equivalence harness.** Switch
   `test_runcmake_yelu.ml` from direct-text to the AST path. If 50/50
   still pass, the AST emit is at parity.
7. **Direct-text emit becomes diagnostic / diff aid.** Keep
   `yelu_tiny_cmake_emit.ml` callable but not on the critical path. Use
   it for two purposes: (a) golden-diff testing during Phase 1
   migration; (b) human inspection when the AST path produces
   surprising text. Remove only after AST parity has held through at
   least one R3 / Y17 milestone.

**Phase 1 done criterion:** production text generation is
`Yelu1 → cmake AST → lang_cmake_pp → text`. All tests green. Direct
text emit kept around but not on the critical path.

### Phase 2 — Parser produces Yelu1

8. **Survey `lang_yelu_parse.ml` → AST production rules.** ~50 rules per
   family (var, string, list, target, install, …). Map each to its Yelu1
   counterpart. The map mostly exists inside `yelu_cmake_to_yelu1.ml`
   already.
9. **Migrate one family at a time, with helpers.** Phase 2 does **not**
   require literally folding all bridge logic into Menhir actions — that
   would make the parser unreadable. Acceptable shapes:
   - parser actions build small Yelu1 fragments via helper builders;
   - or parser builds an intermediate "parse surface" (a thin sum type
     mirroring concrete-syntax shape) that one short pass lowers to
     Yelu1.

    Pick per family; the inline-bridge assertion that R6 added becomes
    "parse → emit_ast → cmake_pp → text non-empty" (no bridge in the
    middle).
10. **R3 genex theory.** Real generator-expression constructors now make
    sense as Yelu1 nodes (not opaque strings), since the parser owns
    them directly. 12 variants per `status.md`.
11. **Move `lang_yelu_cmake.ml` to `yelu_legacy/`.** Parser no longer
    produces it.
12. **Delete `yelu_cmake_to_yelu1.ml`.** Bridge has no inputs left.
13. **Move legacy.** `git mv src/langs/yelu  src/langs/yelu_legacy` for
    everything except `parse`, `lexer`. Update `dune` names.
14. **Repoint binary callers.** Step files in `src/bin/yelu/` move from
    `Lang_yelu_compile.compile` to the new direct path.
15. **Optional: rename `yelu_tiny` → `yelu`.** Pure rename + dune entry
    edit. `yelu_tiny` directory matched its experimental status; once
    it *is* the production code, the name should match.

**Phase 2 done criterion:** production path is
`parse → Yelu1 → emit_ast → cmake_pp → text` with no `yelu_legacy`
imports. Legacy compile stays callable for the oracle test.

## Equivalence oracle (kept callable forever)

The legacy `Lang_yelu_compile.compile` function is the **reference
implementation**. Two oracle shapes, depending on phase:

**Before parser retirement (Phases 1 → mid-2):**

```ocaml
let oracle (prog : Lang_yelu_cmake.yelu_stmt list) =
  let legacy_text  = prog |> Lang_yelu_compile.compile  |> Lang_cmake_pp.pp_to_string in
  let tiny_text    = prog |> Yelu_cmake_to_yelu1.stmt    |> Yelu_tiny_cmake_emit.emit_ast |> Lang_cmake_pp.pp_to_string in
  Alcotest.(check string) "legacy AST → text == tiny AST → text" legacy_text tiny_text
```

**After parser retirement (Phase 2 done):**

```ocaml
let oracle (source : string) =
  let legacy_text =
    source |> Legacy_parse.parse |> Lang_yelu_compile.compile  |> Lang_cmake_pp.pp_to_string in
  let tiny_text =
    source |> Parse.parse        |> Yelu_tiny_cmake_emit.emit_ast |> Lang_cmake_pp.pp_to_string in
  Alcotest.(check string) "legacy source → text == tiny source → text" legacy_text tiny_text
```

The shift is which parser feeds each side — but both sides always end at
`Lang_cmake_pp.pp_to_string` against the same cmake AST, so the
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
warm-up:    is_absolute + list(GET)             ← unblocks Phase 1
phase 1:    emit_ast lands; direct emit demoted to diagnostic aid
phase 2a:   parser refactor (per family + helpers)
phase 2b:   R3 genex first slice (now first-class)
phase 2c:   legacy moved; bridge deleted
y17:        post-retirement typing pass on tiny
delete?:    separate decision, gated on Y17 + production stability
```

Each transition is PR-sized. The full retirement is ~4 k lines of edits
across ~30 commits; most of the work is *moving* code rather than
rewriting it.
