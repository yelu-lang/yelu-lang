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

**Deletion is a separate later decision.** It's gated on Y17 (the
post-retirement typing pass) plus at least one major version of
yelu_tiny shipping without needing legacy as a cross-check.

## End-state goal

The fully retired pipeline:

```
source.ye  →  parse  →  Yelu1 IR  →  emit_ast  →  cmake AST  →  cmake_pp  →  CMakeLists.txt
```

Yelu1 IR is the canonical typed AST. The legacy `Lang_yelu_cmake` AST is
no longer on the production path; it lives in `yelu_legacy/` as the
old reference shape. Emit goes *through* the existing cmake AST + pp
infrastructure (1.4 k lines of well-tested formatting code in
`src/langs/cmake/lang_cmake_pp.ml`) rather than re-implementing text
rendering — there is exactly one cmake pretty-printer in the codebase.

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
| `yelu_cmake_to_yelu1.ml` (bridge)                     | 1,056 | production AST → Yelu1 IR              | retires alongside `lang_yelu_cmake` (Phase 2); merged into the new parser         |
| `yelu_tiny_cmake_emit.ml` (direct text)               |   964 | Yelu1 IR → cmake text                  | **replaced** by `yelu_tiny_cmake_emit_ast.ml` going through cmake AST (Phase 1)   |
| `lang_cmake.ml` + `lang_cmake_pp.ml` + `_utils.ml`    | 2,715 | cmake AST + pretty-printer + ctors     | unchanged — becomes the single canonical text-generation path                     |

## Two phases

**Phase 1 — Emit through cmake AST.** Smaller, no parser churn. The
bridge still runs; only the back end changes.

```
before:  parse → yelu_cmake → bridge → Yelu1 → yelu_tiny_cmake_emit       → text
phase 1: parse → yelu_cmake → bridge → Yelu1 → yelu_tiny_cmake_emit_ast  → cmake AST → cmake_pp → text
```

**Phase 2 — Parser produces Yelu1 directly.** The yelu_cmake AST and
the bridge both retire. This is where Yelu1 *really* replaces
yelu_cmake.

```
phase 2: parse → Yelu1 → yelu_tiny_cmake_emit_ast → cmake AST → cmake_pp → text
```

Phase 1 is bounded (≈1 k lines of refactoring) and unblocks Phase 2
without committing to it. Phase 2 is bigger and benefits from Phase 1
landing first: by then the new back end is proven against the legacy
compile path, so the parser refactor can validate against tiny's emit
in isolation.

## Concrete steps

Items are sized for "small enough that the test suite catches errors
within one commit." Order is dependency-driven.

### Pre-retirement warm-up

These close out open semantic debt before any module moves.

1. **R3 — Genex first slice.** 12 variants per `status.md`. Closes the
   last bridge gap that production parse can produce. **Required
   before Phase 1.**
2. **`Yexpr_is_absolute` real bridge.** Currently degrades to `EBool false`
   at `yelu_cmake_to_yelu1.ml:59`. Small.
3. **`list(GET)` multi-index.** Bridge fails on >1 index at
   `yelu_cmake_to_yelu1.ml:223`. Cmake supports it. Small.

### Phase 1 — Emit through cmake AST

4. **New module `yelu_tiny_cmake_emit_ast.ml`.** Mirrors
   `yelu_tiny_cmake_emit.ml`'s match structure but produces
   `Lang_cmake.exp` values instead of strings. Threads the same
   substitution env (for `ELet` resolution) — substitution happens at
   AST construction time, not at text emit time.
5. **Wire one alt entry point.** Add `Yelu_tiny_cmake_emit_ast.emit ::
   expr → Lang_cmake.exp` next to the existing
   `Yelu_tiny_cmake_emit.emit_script :: expr → string`. Keep both
   callable.
6. **Add a parallel test layer.** Every existing emit test gets a
   companion that pipes through `emit_ast → lang_cmake_pp` and asserts
   string equality with the direct-emit baseline. Where they diverge,
   pick the cmake_pp output as canonical and update the baseline; the
   direct-emit module is the one being retired, so its formatting
   choices don't win.
7. **Repoint runcmake-yelu equivalence harness.** `test_runcmake_yelu.ml`
   currently calls `yelu_tiny_cmake_emit.emit_script` to compare against
   reference cmake. Switch to the AST path. If 50/50 still passes, the
   AST emit is at parity.
8. **Decommission `yelu_tiny_cmake_emit.ml`.** Once all callers have
   moved, delete (or move to `yelu_legacy/` if useful for diff testing).
9. **Rename `yelu_tiny_cmake_emit_ast.ml` → `yelu_tiny_cmake_emit.ml`.**
   Cosmetic — the AST path is now the only path.

**Phase 1 done criterion:** production text generation is
`Yelu1 → cmake AST → lang_cmake_pp → text`. All tests green. Direct
text emit module removed.

### Phase 2 — Parser produces Yelu1

10. **Survey parser → AST production rules.** `lang_yelu_parse.ml` has
    ~50 production-AST-building rules (per family: var, string, list,
    target, install, …). Map each to its Yelu1 IR counterpart. The
    map mostly exists already inside `yelu_cmake_to_yelu1.ml` — Phase 2
    folds the bridge logic into the parser.
11. **Refactor parser, one family at a time.** Each commit migrates one
    production family (e.g. all `Yvar_*` rules → corresponding
    `ECmake*` constructors) and updates the parser tests. The
    inline-bridge assertion that R6 added becomes "parse → emit_ast
    → cmake_pp → text non-empty" (no bridge in the middle).
12. **Move `lang_yelu_cmake.ml` to `yelu_legacy/`.** Once the parser no
    longer produces production AST, the AST type itself is legacy-only.
13. **Delete `yelu_cmake_to_yelu1.ml`.** The bridge has no inputs left.
14. **Move legacy.** `git mv src/langs/yelu  src/langs/yelu_legacy` for
    everything except `parse`, `lexer`. Update `dune` names.
15. **Repoint binary callers.** Step files in `src/bin/yelu/` move
    from `Yelu_langs.Lang_yelu_compile.compile` to the new direct path.
16. **Rename `yelu_tiny` → `yelu`** (optional, do separately). At this
    point `src/langs/yelu_tiny/` *is* the production code; renaming
    matches the language name.

**Phase 2 done criterion:** production path is
`parse → Yelu1 → emit_ast → cmake_pp → text` with no `yelu_legacy`
imports. Legacy compile stays callable for the oracle test.

## Equivalence oracle (kept callable forever)

The legacy `Lang_yelu_compile.compile` function becomes the **reference
implementation**. After retirement, the test suite gains a fixed-point
check:

```ocaml
let oracle prog =
  let legacy_text =
    prog
    |> Lang_yelu_compile.compile
    |> Lang_cmake_pp.pp_to_string
  in
  let tiny_text =
    prog
    |> Yelu_cmake_to_yelu1.stmt
    |> Yelu_tiny_cmake_emit.emit_ast
    |> Lang_cmake_pp.pp_to_string
  in
  Alcotest.(check string) "legacy == tiny" legacy_text tiny_text
```

This is the strongest possible equivalence claim: for every program
the legacy path can compile, the tiny path produces byte-identical
output. It runs on the existing 194-program `test_yelu_compile`
suite. Any future tiny optimization that breaks this oracle is, by
definition, a behavior change — caught immediately.

## What stays callable forever (until separate decision)

- `yelu_legacy.Lang_yelu_compile` — the oracle.
- `yelu_legacy.Lang_yelu_wellform` — comparison baseline for Y17.
- `yelu_legacy.lang_yelu_type` + `fragments/*_check.ml` — same.

## What never gets deleted (without separate decision)

- The `yelu_legacy/` directory in its entirety. Even if Y17 lands a
  better checker, keep legacy until at least one major version of
  yelu has shipped without needing the cross-check.

## Sequencing summary

```
warm-up:    R3 + is_absolute + list(GET)        ← unblocks Phase 1
phase 1:    emit_ast lands, direct emit retires ← unblocks Phase 2
phase 2:    parser produces Yelu1, bridge retires, legacy moved
y17:        post-retirement typing pass on tiny
delete?:    separate decision, gated on Y17 + production stability
```

Each transition is a single PR-sized step. Total scope is small
(~4 k lines of edits across ~30 commits) because most of the work
is *moving* code rather than rewriting it.
