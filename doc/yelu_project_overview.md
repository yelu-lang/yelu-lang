# Yelu — Project Overview

> Last updated: 2026-04-30

## Scope

Yelu is a programmable configuration shell language — a staged DSL for studying
whether regular syntax, explicit namespaces, canonical forms, and local
verification improve model-driven generation and repair. cmake is the first
target; json/yaml/nix are future packs.

**What yelu is not**: a better template language, cmake syntax sugar, or a build
system.

## Architecture

```
                    ┌─────────────────────────────┐
                    │     yelu_stmt (pack)         │
                    │  Ys_target | Ys_var | ...    │
                    │  Yc_include | Yc_foreach ... │
                    └──────────┬──────────────────┘
                               │ compile (type erasure)
                    ┌──────────▼──────────────────┐
                    │     cmake AST               │
                    │  (stringly-typed)           │
                    └──────────┬──────────────────┘
                               │ pretty-print
                    ┌──────────▼──────────────────┐
                    │     CMakeLists.txt           │
                    └─────────────────────────────┘
```

**Two-layer architecture**:

1. **Core layer** (language-agnostic): `LANG_TYPES` substrate signature,
   `Make_*_op` / `Make_*_check` functor pairs per theory — each theory
   defines typed statement constructors and validates expression-level
   types independently.

2. **Pack layer** (per-target): cmake-pack (`lang_yelu_cmake.ml`) instantiates
   all 14 theories against `Cmake_types` and composes the top-level `yelu_stmt`
   sum type. A future json-pack or nix-pack would reuse the core with its own
   statement type.

### Compositional checking

| Stage         | What it checks                                                     | Status                   |
| ------------- | ------------------------------------------------------------------ | ------------------------ |
| `typecheck`   | Expression-level type constraints — per-theory, per-statement      | ✅ 14 theories complete  |
| `wellform`    | Name binding: cvar/target declarations and cross-theory references | ✅ done (2026-05-04)     |
| `effect`      | cmake execution-mode constraints                                   | ⏳ not started           |
| `lower`       | Structural validity during AST → cmake                             | ⚠️ partial               |
| `configure`   | cmake itself: REQUIRED, math, policy                               | ✅ via RunCMake compat   |

Each theory's `Make_*_check` exposes `let stage = Stage_typecheck` and is
enforced via `CHECKER_BASE` module signature in `Cmake_check`.

### Parallel harness: yelu_tiny

Since 2026-05-01 a second implementation track has been growing
alongside the production layers: `src/langs/yelu_tiny/`. It re-shapes
the production AST into two axles:

```
Yelu1 = tiny core + cmake-shaped surfaces  (production-compatible)
Yelu2 = tiny core + idealized theories     (refinement target)
```

The bridge `yelu_cmake_to_yelu1.ml` maps production `yelu_cmake` AST →
Yelu1; `yelu_tiny_translate.ml` lifts Yelu1 ↔ Yelu2; `yelu_tiny_cmake_emit.ml`
renders Yelu1 back to cmake. Each fragment provides a matched
`yelu_theory_*` (Yelu2 ideal) and `yelu_surface_cmake_*` (Yelu1
cmake-shaped) pair.

Milestone status (as of 2026-05-10):

- **Bar #1 — tutorial v1 step1–step12 (root)** ✅ all bridge through tiny;
  step1, 2, 3, 4, 5, 6, 7, 8_table, 10, 12 also configure through real cmake.
- **Bar #2 — every production theory has at least a first slice** ✅ all 14.
- **Bar #3 — real-world cmake rewrites (z3, llvm, torch)** ⏳ not started.

Full implementation history → `doc/worklog_2026_05.md`.
Current TODO → `doc/yelu_tiny/status.md`.

## Current State

### Code inventory

| Layer               | Files | Lines | Description                          |
| ------------------- | ----- | ----- | ------------------------------------ |
| cmake AST + PP      | 3     | 2,715 | All 133 cmake commands, stringly-typed |
| yelu core           | 5     | 2,080 | Types, compiler, utils, cmake-pack   |
| fragments (theories)| 15    | 1,194 | Per-theory functors, 14 theories     |
| yelu_tiny harness   | ~25   | 4,001 | Two-axle composition harness (May 2026) |
| cmake step files    | 36    | 1,560 | Tutorial v1/v2 + CMakeOnly           |
| yelu step files     | 36    | 1,332 | Same, in yelu DSL                    |
| **Total**           | ~120  | ~12,900 |                                    |

### Test infrastructure

| Suite                 | Count  | What it verifies                           |
| --------------------- | ------ | ------------------------------------------ |
| `test_cmake_pp`       | 72     | cmake pretty-printer output                |
| `test_yelu_compile`   | 194    | yelu → cmake compilation correctness       |
| `test_yelu_check`     | 57     | per-theory type checking + wellform        |
| `test_yelu_lexer`     | 25     | lexer for concrete syntax                  |
| `test_yelu_parser`    | 170    | parser for concrete syntax                 |
| `test_yelu_tiny_*`    | 137    | bridge / emit / lift_lower / steps / function |
| **Unit tests total**  | **655**|                                           |
| RunCMake compat       | 61     | yelu scripts vs cmake reference output     |
| cmake-check (v1+v2)   | 35     | structural equivalence via gersemi         |
| CMakeOnly check       | 12     | structural equivalence for CMakeOnly suite |
| file-api-test         | 12     | codemodel-v2 JSON diff (steps 1–12)        |
| end-to-end (`stepN`)  | 12     | Generate → configure → build → run         |
| `test_yelu_tiny_cmake`| 40     | tiny lowerings configure through real cmake |

### 14 Theories

| Theory       | Typecheck        | Declares      | References cross-theory     |
| ------------ | ---------------- | ------------- | --------------------------- |
| `var`        | ✅ non-trivial    | cvars         | —                           |
| `target`     | ✅ non-trivial    | targets       | target names (link, target_*) |
| `install`    | ✅ non-trivial    | —             | declared targets            |
| `test`       | ⚠️ minimal       | —             | declared targets            |
| `property`   | ✗ stub           | output cvars  | target names                |
| `string`     | ✅ non-trivial    | output cvars  | —                           |
| `file`       | ✅ non-trivial    | output cvars  | —                           |
| `path`       | ✅ non-trivial    | output cvars  | —                           |
| `list`       | ✅ non-trivial    | output cvars  | cvars must exist            |
| `find`       | ⚠️ partial       | output cvars  | —                           |
| `try`        | ✅ non-trivial    | output cvars  | —                           |
| `cmake_op`   | ⚠️ partial       | output cvars  | —                           |
| `cond`       | ✅ non-trivial    | —             | —                           |
| `dir`        | ✅ non-trivial    | —             | —                           |

## Gaps

| Gap                       | Category     | Impact                                  |
| ------------------------- | ------------ | --------------------------------------- |
| No CI                     | Infra        | Yelu can break silently                 |
| Website live              | Infra        | ✅ GitHub Pages at yelu-lang.github.io/yelu-lang |
| No concrete parser        | Language     | Yelu is OCaml-hosted, no standalone `.yl` |
| ~~No name binding pass~~  | Checker      | ✅ Done: `lang_yelu_wellform.ml`, 41 tests |
| No effect pass            | Checker      | No execution-mode validation            |
| No systematic lower pass  | Compiler     | Panics on malformed input               |
| Property check is stub    | Checker      | All property ops pass unchecked         |

## Implementation Queue

### Implementation (code-ready)

| ID   | Title                                   | Description                                  |
| ---- | --------------------------------------- | -------------------------------------------- |
| ✅    | Name binding pass                       | Whole-program cvar/target def-use check      |
| —    | Yelu CI                                 | Build + test on push to yelu/**              |
| Y2   | Option combination enumeration          | 2^n boolean combos for step4+, File API diff |
| Y5   | File API cache-v2 diff                  | Extend oracle beyond codemodel-v2            |
| Y12  | Cmake-layer test mirroring              | Sync cmake PP tests with yelu coverage       |

### Design (before coding)

| ID   | Title                                   | Description                                  |
| ---- | --------------------------------------- | -------------------------------------------- |
| Y6   | Semantics hardest to preserve           | Genex, policy stack, find_package search     |
| Y7   | Cache-sensitivity annotations           | `Cache_breaking | Cache_safe | Cache_partial` |
| Y11  | Policy-aware compiler                   | Auto-emit policy preamble per construct      |
| Y13  | Persistent value primitive              | `@cached` with content-addressed store       |
| Y14  | Reserved keyword validation             | Enumerate cmake keywords, warn on clashes    |
| Y15  | Binding feature library                 | Design space (lexical vs global, mutable vs immutable, expr vs stmt). Current: `let` + `set` |
| Y16  | Real-world cmake rewrite                | z3 / llvm / torch builds in yelu, prove structural equivalence |
| Y17  | Types on yelu_tiny                      | Post-retirement: fresh typing pass over tiny once yelu1↔cmake / yelu2↔yelu1 are stable |

### Research (likely papers/material)

| ID   | Title                                   | Description                                  |
| ---- | --------------------------------------- | -------------------------------------------- |
| Y3   | Z3 symbolic equivalence                 | Prove equivalence for all boolean-option inputs |
| Y4   | E-graph investigation                   | Equality saturation over state-transformers  |
| Y8   | Multi-stage core                        | Quote/splice staging across compile/configure |

## Next Steps (suggested order)

1. **CI** — lowest effort, prevents silent regressions. One workflow file.
2. **Name binding** — completes `Stage_typecheck` milestone. ~200 lines, clear interface.
3. **Parser** — Menhir grammar design exists. Makes yelu a standalone language.
4. **Design queue** — Y6, Y7, Y11, Y14: design passes before touching code.

## Documentation Map

| File                            | Purpose                                          |
| ------------------------------- | ------------------------------------------------ |
| `yelu_lang_design.md`           | Language design: staging, types, surface syntax  |
| `yelu_typed_design.md`          | Type system, compositional checking architecture |
| `yelu_lang_coverage.md`         | cmake command coverage, 4-tier roadmap           |
| `yelu_concrete_syntax_parser.md`| Menhir grammar design for concrete syntax        |
| `cmake/comparison.md`           | cmake PL properties, equivalence levels          |
| `cmake/painpoints.md`           | 27 documented cmake pain points                  |
| `cmake/policy.md`               | cmake policy system, CMP* history                |
| `cmake/genex.md`                | Generator expressions design                     |
| `cmake/script.md`               | cmake -P script vs configure mode                |
| `cmake/cache_semantics.md`      | Cache vs normal variable namespace               |
| `cmake/scope_and_control_flow.md` | block / return / PARENT_SCOPE / macro          |
| `cmake/equiv_research.md`       | Z3 / e-graph equivalence research prompts        |
| `yelu_tiny/design.md`           | yelu_tiny harness design notes                   |
| `yelu_tiny/structure.md`        | yelu_tiny module guide                           |
| `yelu_tiny/status.md`           | yelu_tiny current open work                      |
| `yelu_beyond.md`                | Multi-pack architecture, AI language stacks      |
| `yelu_research_framing.md`      | Benchmark design, contamination-aware eval       |
| `yelu_infra_test.md`            | Test harness, dune aliases, gotchas              |
| `worklog_2026_04.md`            | Completed items (Y1, Y9, Y10)                    |
