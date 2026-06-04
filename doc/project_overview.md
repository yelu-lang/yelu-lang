# Yelu — Project Overview

> Last updated: 2026-06-03

## Scope

Yelu is a programmable configuration shell language — a staged DSL for studying
whether regular syntax, explicit namespaces, canonical forms, and local
verification improve model-driven generation and repair. cmake is the first
target; json/yaml/nix are future packs.

**What yelu is not**: a better template language, cmake syntax sugar, or a build
system.

## Architecture

The project hosts two cmake-domain languages and a stringly-typed cmake AST
underneath:

```
  yelu_cmake (cmake-faithful compatibility form)
       ⇅  Yelu_cmake_convert.{to_normal, from_normal}
  yelu_cmake_normal (normalized / reorganized form of the same language)
       │  Yelu_cmake_emit (or Yelu_cmake_emit_debug)
       ▼
  Lang_cmake.exp (stringly-typed AST, mirrors all 133 cmake commands)
       │  Lang_cmake_pp
       ▼
  CMakeLists.txt
```

- **`yelu_cmake`** — the cmake-command-faithful form. Production text generation
  routes through it: step files build it, the concrete-syntax parser produces
  it, `Yelu_cmake_emit` lowers it to `Lang_cmake.exp`. Code lives in
  `src/langs/yelu/yelu_cmake*.ml` plus `src/langs/yelu/fragments/yelu_cmake_<theory>.ml`.
- **`yelu_cmake_normal`** — a normalized decomposition that doesn't have to
  mirror cmake's statement / output-variable shape. Code lives in
  `src/langs/yelu/yelu_cmake_normal_*` and per-theory
  `src/langs/yelu/fragments/yelu_cmake_normal_<theory>.ml`.
- Translation between the two lives in `Yelu_cmake_convert` (`to_normal` /
  `from_normal`).

### Theories

The language is organized in **theories** — per-domain fragments that contribute
constructors, eval arms, and emit arms. Each theory exists in two forms (one in
`yelu_cmake`, one in `yelu_cmake_normal`), composed via `Yelu_cmake_convert`.

- 14 cmake-faithful fragments: `var`, `target`, `string`, `path`, `file`,
  `list`, `find`, `install`, `test`, `try`, `if`, `dir`, `property`, `cmake_op`,
  `store`.
- 16 normalized fragments including the cmake-faithful set plus a small
  general-purpose subset (`bool`, `int`) that is theory-agnostic and a candidate
  for future re-use across packs.

Forward architectural plan (theory-fragment split) at
[`yelu_theory/plan.md`](yelu_theory/plan.md).

### Layered checking

| Stage         | What it checks                                                     | Status                |
| ------------- | ------------------------------------------------------------------ | --------------------- |
| `typecheck`   | Expression-level type constraints — per-theory, per-statement      | retired with Y17 pending |
| `wellform`    | Name binding: cvar/target declarations and cross-theory references | retired with Y17 pending |
| `effect`      | cmake execution-mode constraints                                   | ⏳ not started        |
| `lower`       | Structural validity during AST → cmake                             | ⚠️ partial            |
| `configure`   | cmake itself: REQUIRED, math, policy                               | ✅ via RunCMake compat |

The earlier per-fragment `Stage_typecheck` pass was retired alongside the legacy
production AST (commits up to E1, 2026-05-14). Y17 — a fresh typing pass over
the post-retirement `yelu_cmake` / `yelu_cmake_normal` IR — is the replacement;
tracked in [`yelu_cmake/status.md`](yelu_cmake/status.md) "Open work".

## Current State

### Code layout

| Layer                                                  | Notes                                                     |
| ------------------------------------------------------ | --------------------------------------------------------- |
| `src/langs/cmake/`                                     | Stringly-typed cmake AST + pretty-printer (`Lang_cmake.exp`, `Lang_cmake_pp`). |
| `src/langs/yelu/`                                      | Production: `yelu_cmake` + `yelu_cmake_normal` + parser + emit. |
| `src/langs/yelu/fragments/`                            | 30 per-theory fragments (14 cmake-faithful + 16 normalized). |
| `src/langs/yelu_legacy/`                               | Retired reference; excluded from the `yelu_langs` library via `dune` negative-module list. E2 will `git rm` it after Y17. |
| `src/bin/cmake/v1/`, `src/bin/cmake/v2/`, `src/bin/yelu/v1/`, `src/bin/yelu/v2/`, `src/bin/yelu/` | Tutorial step files + CMakeOnly generators. |
| `tool/cmake_roundtrip/`                                | Bar #3-lite syntactic round-trip oracle (Python + OCaml). |

### Test infrastructure

| Suite                              | Count    | What it verifies                                              |
| ---------------------------------- | -------: | ------------------------------------------------------------- |
| Unit tests (`dune test`)           | ~1,010   | Pretty-printer, compile, parse, eval, lift/lower, steps, etc. |
| `make runcmake-yelu`               | 50 / 50  | yelu-generated scripts vs cmake reference output.             |
| `make cmake-only-check`            | 12 / 12  | Structural equivalence for `Tests/CMakeOnly/`.                |
| `make cmake-check-v1`              | 24 / 24  | Tutorial v1 structural-equivalence via gersemi.               |
| `make cmake-check-v2`              | 11 / 11  | Tutorial v2 structural-equivalence via gersemi.               |
| `make file-api-test`               | 12 / 12  | codemodel-v2 JSON diff on tutorial steps.                     |
| End-to-end (`make step1`–`step12`) | 12       | Generate → configure → build → run.                           |
| Bar #3-lite parse-print round-trip | 740 / 740 (canonical) + 3004 / 3035 (full llvm-project) | tutorial 25/25 + fmt 11/11 + z3 108/108 + llvm/llvm 596/596 = canonical 740. Full llvm-project (3035 files) adds 3004 OK + 1 FORMAT + 30 STRUCT pre-existing. See [`../probes/parse_print_oracle.md`](../probes/parse_print_oracle.md). |
| fmt cache matrix smoke             | 24 / 24 cells | Predicted vs real cmake cache per (option × ON/OFF); median matched=20, mismatched=0, real-only=0, pred-only=0. See [`../probes/cache_matrix.md`](../probes/cache_matrix.md). |

`make cmake-commands` has pre-existing cmake build issues (not blocking).
`test_yelu_compile::ylet chain` has a pre-existing single-test failure
unrelated to recent work.

### Project-level milestones

- **Bar #1 — tutorial v1 step1–step12.** ✅ All bridge through `yelu_cmake`;
  all 12 configure through real cmake; 12 file-api JSON diffs match.
- **Bar #2 — every production theory has at least a first slice.** ✅ All 14.
- **Bar #3-lite — parse-print cmake round-trip on z3 + llvm.** ✅ Shipped
  2026-05-15..20. STRUCT=0 / FORMAT=0 across 729 files in tutorial + z3 +
  llvm canonical. Surfaced and fixed 5 production-IR bugs. Audit-ready
  writeup at [`../probes/parse_print_oracle.md`](../probes/parse_print_oracle.md).
  Extended 2026-06-03 to include fmt (11/11 OK) and the full llvm-project
  corpus (3004/3035 OK + 1 FORMAT + 30 STRUCT pre-existing).
- **Cache namespace + `-D` cmd-line input.** ✅ Shipped 2026-06-01.
  `ECmakeSetCache` and `ECmakeOption` now write into `env.cache_vars`
  (separate from `env.frames`); `-D` populates cache before eval so
  `option()` is correctly a NO-OP when the entry exists. Plan in
  [`yelu_cmake/cache_plan.md`](yelu_cmake/cache_plan.md).
- **fmt predictor probe complete.** ✅ Shipped 2026-06-03. 24-cell matrix
  (11 options × ON/OFF) — all cells perfect: real-only=0, mismatched=0,
  pred-only=0, median matched 20. Closing it required:
  - `include()` recursive eval + cmake stdlib `Modules/` path search
  - `add_subdirectory()` recursion via `subdir_loader` callback
  - `${X}` substitution unified via `substitute env s`
  - Cond compounds (`VERSION_*`, `IN_LIST`, `MATCHES`, `LE/GE`) +
    unaries (`EXISTS`, `COMMAND`, `IS_ABSOLUTE`) + recursive-descent
    parser
  - `find_program` / `find_path` / `find_library` / `find_file` stubs
    (NOTFOUND-direction); `find_package(Threads)` whitelist; `try_compile`
    stub (FALSE-direction)
  - `ECmakeReturn` bridge from `C.Return`
  - Smart `Set_cache` docstring + dynamic `CACHE TYPE` printer
  - `option()` canonicalization via `expect_bool`
  - Function/macro/`Apply` dispatch + ARGN
  - `bool_literal_of_string` parse-time consolidation
  Audit-ready writeup at [`../probes/fmt/README.md`](../probes/fmt/README.md).
- **Bar #3 — real-world cmake hand-rewrites (z3 / llvm / torch).** ⏳ Not
  started; the manifesto-level "does this scale" test. Next probe will
  pick the second project per [`../probes/candidates.md`](probes/candidates.md).

Full chronological history in [`worklog/worklog_2026_05.md`](worklog/worklog_2026_05.md)
and [`worklog/worklog_2026_04.md`](worklog/worklog_2026_04.md). Current TODOs
in [`yelu_cmake/status.md`](yelu_cmake/status.md).

## Gaps

| Gap                              | Category     | Notes                                                |
| -------------------------------- | ------------ | ---------------------------------------------------- |
| No CI                            | Infra        | Yelu can break silently.                             |
| ~~No concrete-syntax parser~~    | Language     | ✅ `Yelu_parse` (Angstrom + pure OCaml, 2026-05-04). |
| ~~Retirement of yelu_legacy~~    | Refactor     | ✅ Through E1 (2026-05-14); E2 (delete) pending Y17. |
| No fresh typing pass             | Checker      | Y17 — design ground prepared by theory-fragment split. |
| Lossy `Lang_cmake_pp` arms       | Compiler     | Surfaced by Bar #3-lite; tracked in `yelu_cmake/status.md`. |
| No effect pass                   | Checker      | No execution-mode validation.                        |
| No systematic lower pass         | Compiler     | Panics on malformed input.                           |
| Comments inside argument lists   | IR shape     | Currently dropped; whether IR should carry them is open. |

## Implementation Queue

### Code-ready next steps

| ID  | Title                                | Description                                                   |
| --- | ------------------------------------ | ------------------------------------------------------------- |
| —   | IR-printer cleanup (Bar #3-lite follow-up) | Tier 1/2/3 plan in [`yelu_cmake/status.md`](yelu_cmake/status.md). |
| —   | Yelu CI                              | Build + test on push.                                         |
| Y2  | Option combination enumeration       | 2^n boolean combos for step4+, File API diff.                 |
| Y5  | File API cache-v2 diff               | Extend oracle beyond codemodel-v2.                            |
| Y12 | Cmake-layer test mirroring           | Sync cmake PP tests with yelu coverage.                       |
| E2  | Delete `yelu_legacy/`                | Mechanical follow-up to E1; gated on Y17 not needing it.      |

### Design (before coding)

| ID  | Title                          | Description                                                          |
| --- | ------------------------------ | -------------------------------------------------------------------- |
| Y6  | Semantics hardest to preserve  | Genex, policy stack, find_package search.                            |
| Y7  | Cache-sensitivity annotations  | `Cache_breaking | Cache_safe | Cache_partial`.                       |
| Y11 | Policy-aware compiler          | Auto-emit policy preamble per construct.                             |
| Y13 | Persistent value primitive     | `@cached` with content-addressed store.                              |
| Y14 | Reserved keyword validation    | Enumerate cmake keywords, warn on clashes.                           |
| Y15 | Binding feature library        | Design space (lexical/global, mutable/immutable, expr/stmt).         |
| Y16 | Real-world cmake hand-rewrite  | z3 / llvm / torch builds in yelu, prove structural equivalence.      |
| Y17 | Types on yelu_cmake            | Fresh typing pass over post-retirement IR (replaces retired per-fragment `Stage_typecheck`). |

### Research (likely papers / material)

| ID  | Title                   | Description                                          |
| --- | ----------------------- | ---------------------------------------------------- |
| Y3  | Z3 symbolic equivalence | Prove equivalence for all boolean-option inputs.     |
| Y4  | E-graph investigation   | Equality saturation over state-transformers.         |
| Y8  | Multi-stage core        | Quote/splice staging across compile/configure.       |

## Documentation Map

| File                                       | Purpose                                                            |
| ------------------------------------------ | ------------------------------------------------------------------ |
| `manifesto.md`                             | Project manifesto: thesis, falsifiability, layered argument.       |
| `infra_test.md`                            | Test harness, dune aliases, gotchas.                               |
| `research/research_framing.md`             | Benchmark design, contamination-aware eval (distilled framing).    |
| `research/beyond.md`                       | Multi-pack architecture, AI language stacks (speculative, 中文).   |
| `lang/lang_design.md`                      | Language design: staging, types, surface syntax.                   |
| `lang/lang_coverage.md`                    | cmake command coverage tracker.                                    |
| `lang/typed_design.md`                     | Type system design space (deferred; Y17 substrate).                |
| `lang/syntax_tiers.md`                     | Concrete syntax tier plan.                                         |
| `lang/concrete_syntax_parser.md`           | Implemented two-pass parser (Angstrom + pure OCaml).               |
| `yelu_cmake/design.md`                     | Durable design notes for the yelu_cmake harness.                   |
| `yelu_cmake/structure.md`                  | Code-anchored guide to the yelu_cmake modules.                     |
| `yelu_cmake/cmake_vs_normal.md`            | yc ↔ ycn ecosystem comparison: per-theory fragment coverage.       |
| `yelu_cmake/io_architecture.md`            | I/O library/runner split + callback-via-env pattern (include_loader, subdir_loader). |
| `yelu_cmake/cache_plan.md`                 | Active plan: cache namespace + `-D` cmd-line input (shipped 2026-06-01). |
| `yelu_cmake/status.md`                     | Living tracker for current open work (IR cleanup, Y17, E2, etc.).  |
| `../probes/README.md`                         | Probe cluster intro: real-world cmake projects as predictor testbeds. |
| `../probes/candidates.md`                     | Shortlist of next projects to probe.                               |
| `probes/parse_print_oracle.md` | Parse-print round-trip oracle audit (was bar3_lite.md).            |
| `probes/cache_matrix.md`       | fmt matrix smoke coverage pipeline walkthrough.                    |
| `../probes/fmt/README.md`            | fmt probe status — 24/24 cells perfect; adaptation footprint.      |
| `../probes/fmt/probe_report.md`      | fmt 2026-06-01 pre-implementation scoping (SUPERSEDED banner).     |
| `../probes/z3/README.md`             | z3 probe — 108/108 parse-print OK; matrix not yet built.           |
| `../probes/llvm/README.md`           | llvm probe — 3004/3035 parse-print OK; matrix not yet built.       |
| `yelu_theory/plan.md`                      | Theory-fragment structural split plan.                             |
| `yelu_theory/boolean_and_theories.md`      | Post-mortem of the `yelu_cond` / `yelu_expr` merge; design conclusions. |
| `yelu_theory/extensible_expr_design.md`    | Original framing of the extensible-expression problem.             |
| `cmake/painpoints.md`                      | 27 documented cmake pain points.                                   |
| `cmake/comparison.md`                      | cmake PL properties, equivalence levels.                           |
| `cmake/policy.md`                          | cmake policy system, CMP* history.                                 |
| `cmake/genex.md`                           | Generator expressions design.                                      |
| `cmake/script.md`                          | cmake -P script vs configure mode.                                 |
| `cmake/cache_semantics.md`                 | Cache vs normal variable namespace.                                |
| `cmake/scope_and_control_flow.md`          | Block / return / PARENT_SCOPE / macro semantics.                   |
| `cmake/equiv_research.md`                  | Z3 / e-graph equivalence research prompts.                         |
| `worklog/worklog_2026_04.md`               | Completed items (Y1, Y9, Y10).                                     |
| `worklog/worklog_2026_05.md`               | yelu_cmake harness Tier A–F + retirement + Bar #3-lite archive.    |
