# Claude Code — Yelu Project Guide

> **Scope**: Yelu is now a standalone project at `/home/red/code/research/yelu`
> (extracted from tola monorepo on 2026-05-04). Remote: `github.com/yelu-lang/yelu-lang`.

## Build & Run

All commands run from the yelu repo root (`dune-project` lives here).

```sh
dune build                                      # everything
dune build src/langs/ src/bin/yelu/             # yelu layer + main binary
dune build src/langs/ src/bin/cmake_only/       # cmake-only generators
dune test                                       # all unit tests (923 tests)
```

After Phase 1 of retirement, the production yelu compile path is

```
source.yelu → parse → yelu_cmake → emit_ast → Lang_cmake.exp → cmake_pp → text
```

with the byte-equality oracle in `test_yelu_compile.ml` asserting every
program produces byte-identical text against the legacy `Lang_yelu_compile`
reference. Watch for the `[emit_ast oracle] covered=194 uncovered=0`
line at the end of `dune test` — any drift is a Phase 1 regression. The
retirement journey is archived in
[doc/worklog/worklog_2026_05.md](doc/worklog/worklog_2026_05.md);
[doc/yelu_cmake/status.md](doc/yelu_cmake/status.md) tracks any
remaining items (E2, Y17).

Make targets (from repo root):

```sh
make test                # dune test (unit tests)
make cmake-check         # structural equivalence check (requires gersemi)
make cmake-check-v1      # v1 tutorial steps (24 checks)
make cmake-check-v2      # v2 tutorial steps (11 checks)
make cmake-only-check    # CMakeOnly test suite (12 checks)
make runcmake-compat     # RunCMake positive-test compat suite (61 tests)
make runcmake-yelu       # yelu-generated scripts vs reference (script-pair)
make cmake-commands      # cmake_commands build-level tests
make file-api-test       # file-api step pairs (configure + inspect)
make coverage            # all of the above
make step1 .. step12     # generate → cmake configure → build → run
```

## Key Source Files

### Tool bridge (cmake-text ↔ IR)

| Directory / File                              | Purpose                                      |
| --------------------------------------------- | -------------------------------------------- |
| `src/langs/drivers/yc_driver.ml`              | yc ops: parse×4, print/compile×3, eval, convert, check |
| `src/langs/drivers/ycn_driver.ml`             | ycn ops: parse, print/compile, eval, check |
| `src/langs/drivers/cmake_driver.ml`            | cmake (IR+text): parse (tool+code), print (code), print_canon (tool:gersemi), eval (tool:cmake), check, to/from yc |
| `src/langs/drivers/yc_to_cmake.ml`            | Pipeline: .yc → yc → cmake AST → cmake text |
| `src/langs/drivers/cmake_to_yc.ml`            | Pipeline: cmake text → JSON CST → cmake AST → yc |
| `src/langs/drivers/yc_ycn.ml`                 | Pipeline: yc ↔ ycn |
| `tool/cmake_text/`                            | External tools: cmake_to_json.py, cmake_reprint.ml, cmake_cache_scan.ml, cmake_name_index.ml, cmake_strip_comments.py, cmake_roundtrip_oracle.sh, cmake_reserved_vars.tsv |

### cmake layer (stringly-typed AST)

| File                                  | Purpose                                      |
| ------------------------------------- | -------------------------------------------- |
| `src/langs/cmake/lang_cmake.ml`       | CMake AST — all 133 commands, stringly-typed |
| `src/langs/cmake/lang_cmake_pp.ml`    | Pretty printer (AST → CMake text)            |
| `src/langs/cmake/lang_cmake_utils.ml` | Ergonomic AST constructors                   |

### yelu layer (typed surface language)

| File                                   | Purpose                                                          |
| -------------------------------------- | ---------------------------------------------------------------- |
| `src/langs/yelu/yelu_parse.ml`                 | Concrete-syntax parser → `yelu_cmake.expr`                       |
| `src/langs/yelu/yelu_lexer.ml`                 | Shared tokens                                                    |
| `src/langs/yelu/yelu_cmake.ml`                 | Core `yelu_cmake` types + env + eval primitives                  |
| `src/langs/yelu/yelu_cmake_emit.ml`            | `yelu_cmake.expr` → `Lang_cmake.exp` (production emit)           |
| `src/langs/yelu/yelu_cmake_emit_debug.ml`      | Direct-text emit (debug aid)                                     |
| `src/langs/yelu/yelu_cmake_eval.ml`            | `yelu_cmake` evaluator                                           |
| `src/langs/yelu/yelu_cmake_normal_eval.ml`     | `yelu_cmake_normal` evaluator                                    |
| `src/langs/yelu/yelu_cmake_convert.ml`         | `to_normal` / `from_normal` between the two languages            |
| `src/langs/yelu/yelu_cmake_utils.ml`           | Ergonomic ctor module for `yelu_cmake.expr`                      |
| `src/langs/yelu/fragments/yelu_cmake_<theory>.ml`         | Per-theory `yelu_cmake` ctors (target, string, list, …) |
| `src/langs/yelu/fragments/yelu_cmake_normal_<theory>.ml`  | Per-theory `yelu_cmake_normal` ctors                    |
| `src/langs/yelu_legacy/yelu_cmake_legacy_bridge.ml` | Legacy `Lang_yelu_cmake` AST → `yelu_cmake.expr`; reference-only after G |
| `src/langs/yelu_legacy/lang_yelu_parse.ml`     | Legacy parser → `Lang_yelu_cmake` AST; still feeds the byte oracle |
| `src/langs/yelu_legacy/lang_yelu.ml`           | Core: `LANG_TYPES`, `Make_stmt` functor bundle (relocated to legacy 2026-05-11) |
| `src/langs/yelu_legacy/lang_yelu_type.ml`      | Type universe, `checking_stage`, `CHECKER_BASE`                  |
| `src/langs/yelu_legacy/lang_yelu_cmake.ml`     | Cmake-pack: `yelu_stmt`, `Cmake_check`, 14 theory instantiations |
| `src/langs/yelu_legacy/lang_yelu_compile.ml`   | Compiler: type erasure yelu → cmake AST (legacy ref for byte oracle) |
| `src/langs/yelu_legacy/lang_yelu_utils.ml`     | Ergonomic constructors for building yelu AST                     |
| `src/langs/yelu_legacy/lang_yelu_wellform.ml`  | Wellform pass: whole-program cvar/target name binding check      |

### Fragments (per-theory functors, `src/langs/yelu_legacy/fragments/`)

Each fragment defines a `Make_*_op (T)` / `Make_*_check (T)` functor pair over `LANG_TYPES`.
All 14 `Make_*_check` modules expose `let stage = Stage_typecheck`, enforced by `CHECKER_BASE`.

| File                    | Lines | Theory                                      |
| ----------------------- | ----- | ------------------------------------------- |
| `lang_yelu_var.ml`      | 44    | Variable set/unset/cache                    |
| `lang_yelu_target.ml`   | 164   | Target (add_library, link, compile options) |
| `lang_yelu_string.ml`   | 136   | String operations                           |
| `lang_yelu_path.ml`     | 135   | Path operations                             |
| `lang_yelu_file.ml`     | 110   | File I/O                                    |
| `lang_yelu_cond.ml`     | 72    | Conditions                                  |
| `lang_yelu_list.ml`     | 67    | List operations                             |
| `lang_yelu_property.ml` | 66    | Property (get/set/define)                   |
| `lang_yelu_install.ml`  | 65    | Install rules                               |
| `lang_yelu_try.ml`      | 65    | try_compile/run                             |
| `lang_yelu_find.ml`     | 81    | find_package/library/path                   |
| `lang_yelu_cmake_op.ml` | 82    | cmake_language, math, execute_process       |
| `lang_yelu_dir.ml`      | 37    | Directory ops                               |
| `lang_yelu_test.ml`     | 20    | Test ops                                    |
| `lang_yelu_genex.ml`    | 50    | Generator expressions                       |

### Step files (tutorial, CMakeOnly generators, debug)

| Directory              | Count | Purpose                                |
| ---------------------- | ----- | -------------------------------------- |
| `src/bin/cmake/v1/`       | 25    | CMake tutorial v1 reference generators |
| `src/bin/cmake/v2/`       | 11    | CMake tutorial v2 reference generators |
| `src/bin/yelu/v1/`        | 25    | Same tutorials in yelu DSL             |
| `src/bin/yelu/v2/`        | 11    | Same tutorials in yelu DSL             |
| `src/bin/yelu/` (top)     | 1     | Main CLI binary (`yelu.ml`)            |
| `src/bin/yelu/common/`    | 1     | Shared step utilities (`step_common`)  |
| `src/bin/cmake_only/`     | 12    | CMakeOnly test suite generators        |
| `src/bin/debug/`          | 2     | Ad-hoc parser/lexer debug scripts      |

### Tests

| File                                       | Tests | Purpose                                                    |
| ------------------------------------------ | ----- | ---------------------------------------------------------- |
| `test/test-cmake/test_cmake_pp.ml`         | 72    | cmake pretty-printer                                       |
| `test/test-yelu/test_yelu_compile.ml`      | 194   | yelu → cmake compilation                                   |
| `test/test-yelu/test_yelu_check.ml`        | 57    | per-theory type checking + wellform name binding           |
| `test/test-yelu/test_yelu_lexer.ml`        | 31    | concrete-syntax lexer (incl. `$foo` sugar + enum-constructor normalization) |
| `test/test-yelu/test_yelu_parse.ml`        | 170   | concrete-syntax parser                                     |
| `test/test-yelu/test_yelu_bridge.ml`       | 43    | production yelu_cmake AST → yelu_cmake (via legacy bridge) |
| `test/test-yelu/test_yelu_emit_debug.ml`   | 3     | yelu_cmake → cmake text (debug direct-emit path)           |
| `test/test-yelu/test_yelu_emit.ml`         | —     | yelu_cmake → `Lang_cmake.exp` → cmake text (production emit) |
| `test/test-yelu/test_yelu_lift_lower.ml`   | 65    | yelu_cmake ↔ yelu_cmake_normal roundtrip (file name retains pre-rename "lift_lower" vocab) |
| `test/test-yelu/test_yelu_steps.ml`        | 19    | tutorial v1 step1–step12 + 8_table + 11_config + ctest     |
| `test/test-yelu/test_yelu_function.ml`     | 14    | F2: dynamic scope / shallow binding                        |
| `test/test-yelu/test_yc_cst_bridge.ml`     | 47    | emit-bridge oracle (`emit(lower(parse_cst)) == emit(parse_ast)`) + comment placement + **surface canonicalization** regression (`$foo`, `'`/`"` quotes, enum constructors) |
| `test/test-yelu/test_yc_manifest.ml`       | 4     | **co-truth lock**: manifest vocabulary ≡ providers (commands, reserved words, **enum constructors ≡ `Yelu_lexer.constr_names`**) |
| `test/test-yelu/test_yc_tmgrammar.ml`      | 4     | TextMate vocabulary-rule generation (regex escaping, longest-first, `\b` bounds) |
| `test/test-runcmake/test_yelu_cmake.ml`    | 40    | yelu_cmake lowerings configure through real cmake          |
| `test/test-runcmake/` (other)              | 37    | cmake -P compat + yelu scripts                             |
| `test/test-file-api/`                      | —     | codemodel-v2 JSON diff                                     |
| `test/test_deref_probes.py`                | 23    | cmake **ground-truth** deref probes (`foo`/`${foo}`/`"${foo}"`, nesting, parse-error negatives) — pinned against real cmake, run via `python3` |
| `test/test-tmgrammar/` (dune `(diff)`)     | 1     | **freshness lock**: committed `yc.tmLanguage.json` must byte-match `yelu tmgrammar`; drift fails `dune test`, fix is `dune promote` |

Total unit: 923 (dune test). Total cmake-backed: 40. (The table lists the
load-bearing suites; the full `dune test` count includes the smaller
per-theory and remaining-command suites not enumerated above.)

### Documentation

| File                                 | Purpose                                             |
| ------------------------------------ | --------------------------------------------------- |
| `doc/manifesto.md`                    | Project manifesto: thesis, falsifiability, approach |
| `doc/project_overview.md`             | Full project audit: code, tests, gaps, TODOs        |
| `doc/lang/typed_design.md`            | Type system, compositional checking architecture    |
| `doc/lang/lang_design.md`             | Language design: staging, types, surface syntax     |
| `doc/lang/lang_coverage.md`           | cmake command coverage tracker                      |
| `doc/lang/syntax_tiers.md`            | Concrete syntax tier plan                           |
| `doc/lang/concrete_syntax_parser.md`  | Implemented two-pass parser (Angstrom + pure OCaml) |
| `doc/lang/surface_lsp_framework.md`   | Surface syntax + LSP design exploration (yc-first): driver-as-plug, CST/spans, manifest-as-co-truth, TextMate Milestone 0 |
| `doc/lang/surface_status.md`          | Living tracker for the surface track (highlighter→formatter→LSP): phases, CST-lite migration via emit-bridge oracle |
| `doc/lang/yc_syntax_critique.md`      | yc surface-syntax design + open items. The no-ALL_CAPS `~`-half pass is **complete** (flags / value-labels / recursive value grammar shapes 2–3; shipped arc in worklog 2026-06); keeps the design rationale + the grouped remaining work. Next: the labeled-only pass |
| `doc/lang/var_centric_design.md`      | Postponed direction: value-default reads (bare `foo` = value, name explicit). Belongs in ycn not yc; ties to tc_name / Y17; needs a frequency study |
| `doc/lang/casing_design.md`           | Casing lanes — **shipped** (enum constructors `Public` no-colon, property scopes, Y14 reserved-word reject) as part of the `~`-half pass; design rationale + open lanes (dotted globals→ycn, CamelCase compat-enum table, oddball escape, booleans) |
| `doc/cmake/painpoints.md`            | 27 documented cmake pain points                     |
| `doc/cmake/comparison.md`            | cmake PL properties, equivalence levels             |
| `doc/cmake/policy.md`                | cmake policy system, CMP* history                   |
| `doc/cmake/genex.md`                 | Generator expressions design                        |
| `doc/cmake/script.md`                | cmake -P script vs configure mode                   |
| `doc/cmake/cache_semantics.md`       | Cmake cache vs normal variable namespace            |
| `doc/cmake/var_reference_semantics.md` | `foo` vs `${foo}` vs `"${foo}"` empirics (cmake 4.3.1): `${}` = variable expansion (not deref); arity/split/elision rules; quoting is a compositional wrapper over interpolated content; yc unsoundness (always-quotes, cache-invisible) + `EUnquoted` plan |
| `doc/cmake/scope_and_control_flow.md` | Block / return / PARENT_SCOPE / macro semantics    |
| `doc/cmake/equiv_research.md`        | Z3 / e-graph equivalence research prompts           |
| `probes/README.md`                | Probe cluster intro: real-world cmake projects as predictor testbeds; per-project + methodology layout |
| `probes/candidates.md`            | Candidate open-source cmake projects for ycn benchmarking (5-project first round) |
| `probes/cache_matrix.md`   | fmt matrix smoke coverage pipeline — static-option-discovery / parse-once / per-cell real-vs-predicted diff / classifier tier filter / cross-cell rollups |
| `doc/worklog/worklog_2026_06.md` | Worklog June 2026 — parse-print oracle close, fmT migration, driver architecture |
| `probes/fmt/README.md`   | fmt probe status — 24/24 cells matched, 11/11 parse-print OK, project spec (12 OPTIONs + observations), adaptation footprint, hybrid pilot result |
| `probes/fmt/migration_status.md` | fmt full-project migration status — all 7 phases closed; explains the configure-time matrix oracle, the `raw_cmake` escape, and the unverified Windows / CUDA branches |
| `probes/z3/README.md`    | z3 probe status — 108/108 parse-print OK, matrix not yet built |
| `probes/llvm/README.md`  | llvm probe status — 3004/3035 parse-print OK (30 pre-existing STRUCT), matrix not yet built |
| `doc/research/beyond.md`              | Multi-pack architecture, AI language stacks (speculative, 中文) |
| `doc/research/research_framing.md`    | Benchmark design, contamination-aware eval          |
| `doc/infra_test.md`                   | Test harness, dune aliases, gotchas                 |
| `doc/yelu_theory/plan.md`             | Theory-fragment structural split plan               |
| `doc/yelu_theory/boolean_and_theories.md` | Post-mortem of yelu_cond / yelu_expr merge      |
| `doc/yelu_theory/extensible_expr_design.md` | Extensible-expression design problem          |
| `doc/worklog/worklog_2026_04.md`     | Completed items (Y1, Y9, Y10)                       |
| `doc/worklog/worklog_2026_05.md`     | yelu_cmake harness Tier A–F + retirement archive    |
| `doc/yelu_cmake/design.md`            | Durable design notes for the yelu_cmake harness     |
| `doc/yelu_cmake/structure.md`         | Code-anchored guide to the yelu_cmake modules       |
| `doc/yelu_cmake/cmake_vs_normal.md`   | yelu_cmake ↔ yelu_cmake_normal ecosystem comparison (parser/eval/emit coverage, per-fragment ctor counts, gaps) |
| `doc/yelu_cmake/io_architecture.md`   | I/O architecture: library/runner split, callback-via-env pattern, relationship to a future ycn module-import feature |
| `doc/yelu_cmake/hybrid_strategy.md`   | Y16 reframed as gradual hybrid adoption (side-by-side .yc + .cmake, or whole-file with raw_cmake escape). cmake-as-assembly framing; no embedded-in-cmake shape. |
| `doc/yelu_cmake/ycn_concrete_syntax.md` | Design notes for a future concrete-syntax parser for `yelu_cmake_normal`. No implementation; uses the lift_lower 65-test corpus as design substrate. |
| `doc/yelu_cmake/driver.md`            | Merged pipelines graph + tool-interface matrix + per-language driver modules + cross-language pipeline utils |
| `doc/yelu_cmake/ir_tiers.md`          | 4-tier IR fidelity: typed → cmake_lang → yc_raw → yc_apply. Parser fallback, string-as-enum plan. |
| `doc/yelu_cmake/status.md`            | Living tracker: current open work for yelu_cmake    |

## Architecture

### Two-layer design

```
  yelu (core)     ← language-agnostic: LANG_TYPES, Make_stmt
    │
  cmake-pack       ← target-specific: yelu_stmt, Cmake_check
    │
  cmake AST        ← stringly-typed, mirrors real cmake
    │
  CMakeLists.txt   ← output, verified against reference
```

The core is a collection of **theories** — 14 `Make_*_op` / `Make_*_check` functor
pairs over a shared `LANG_TYPES` substrate. Each theory defines typed constructors
for one cmake command family and validates expression-level types independently.
Theories compose via `Make_stmt` in `lang_yelu.ml`; the cmake-pack (`lang_yelu_cmake.ml`)
is the integration point where all 14 theories are instantiated against `Cmake_types`.

### yelu_cmake / yelu_cmake_normal composition

The composition harness in `src/langs/yelu/` (formerly `yelu_tiny/`,
renamed in commit `ad6deb8` to align with the production names) defines
two languages on a shared extensible-variant core:

- **`yelu_cmake`** — cmake-faithful surface. 14 theory fragments under
  `fragments/yelu_cmake_<theory>.ml`. Each fragment extends
  `Yelu_cmake.expr` with `ECmake*` constructors that mirror a cmake
  command family (target, install, find, …).
- **`yelu_cmake_normal`** — normalized form. 16 fragments under
  `fragments/yelu_cmake_normal_<theory>.ml`. Same 14 theories plus
  `bool` and `int` (theory primitives the cmake form folds into
  command-specific shapes — e.g. `option(var help ON)` doesn't carry
  a separate `EBool true`). Mutations explicit via `ESetVar`; no
  output-var sugar.

`yelu_cmake_convert.ml` provides `to_normal` / `from_normal` — pure
syntactic rewrites, ~1,750 LOC. The almost-roundtrip property
`from_normal ∘ to_normal ≡ identity-modulo-emission` is exercised by
`test/test-yelu/test_yelu_lift_lower.ml` (65 tests; file name retains
pre-rename "lift_lower" vocab). `yelu_cmake_eval.ml` and
`yelu_cmake_normal_eval.ml` are the dual evaluators.

The yelu_cmake ↔ yelu_cmake_normal bridge is **not on the production
emit path** today — production goes
`yelu_parse → yelu_cmake → yelu_cmake_emit → Lang_cmake.exp`. The
normal form is the substrate future analysis / optimization passes
will operate on (informing Y17 typing and behavior-level equivalence
work). Details in `doc/worklog/worklog_2026_05.md` and
`THEORY_COMPOSITION_PLAN.md`.

### Type system (key types in `lang_yelu_cmake.ml`)

- **`tc_name = { ns : cmake_namespace; name : string }`** — unified cmake named entity.
  `ns` is one of `Ns_var | Ns_target | Ns_cache | Ns_env | Ns_command | Ns_module |
  Ns_test | Ns_export | Ns_property | Ns_unknown`.
  Aliases: `yelu_cvar = tc_name`, `yelu_target = tc_name`.
- **`yc_string`** — 4 variants: `Ycs_path | Ycs_keyword | Ycs_string | Ycs_eval`.
- **`yelu_expr`** — 4 constructors: `Yexpr_name of tc_name | Yexpr_string of yc_string |
  Yexpr_bool of bool | Yexpr_var of yelu_var`.
- **`yelu_var = Yvar of string`** — compile-time binding variable.

### Compositional checking

Checking decomposes into distinct passes, each catching a different class of error:

| Stage       | What it checks                                                     | Status                 |
| ----------- | ------------------------------------------------------------------ | ---------------------- |
| `typecheck` | Expression-level type constraints — per-theory, per-statement      | ✅ 14 theories complete |
| `wellform`  | Name binding: cvar/target declarations and cross-theory ref checks | ✅ done (2026-05-04)    |
| `effect`    | cmake execution-mode constraints                                   | ⏳ not started          |
| `lower`     | Structural validity during AST → cmake                             | ⚠️ partial              |
| `configure` | cmake itself: REQUIRED, math, policy                               | ✅ via RunCMake compat  |

Each `Make_*_check` module exposes `let stage = Stage_typecheck`. The `CHECKER_BASE`
module type (in `lang_yelu_type.ml`) enforces this contract; `Cmake_check` has a
first-class module list that type-checks all 14 instantiations at compile time:

```ocaml
let _ : (module CHECKER_BASE) list = [
  (module Cond_check); (module Str_check); ... (* 14 total *)
]
```

`typecheck` is per-theory and per-statement. `wellform` is cross-theory and
whole-program — a target declared in `target` theory is referenced in `install`/
`test`/`property` theory, so no single theory can resolve this alone.

See [doc/lang/typed_design.md](doc/lang/typed_design.md) for the full design.

## Current State

> Session history → [doc/worklog/worklog_2026_04.md](doc/worklog/worklog_2026_04.md).
> Full audit → [doc/project_overview.md](doc/project_overview.md).

Key milestones: wellform pass (Y1), parser + concrete syntax (in progress), 408 tests.

### 14 theories status

| Theory     | Typecheck | Declares     | References cross-theory |
| ---------- | --------- | ------------ | ----------------------- |
| `var`      | ✅         | cvars        | —                       |
| `target`   | ✅         | targets      | target names            |
| `install`  | ✅         | —            | declared targets        |
| `test`     | ⚠️ minimal | —            | declared targets        |
| `property` | ✗ stub    | output cvars | target names            |
| `string`   | ✅         | output cvars | —                       |
| `file`     | ✅         | output cvars | —                       |
| `path`     | ✅         | output cvars | —                       |
| `list`     | ✅         | output cvars | cvars must exist        |
| `find`     | ⚠️ partial | output cvars | —                       |
| `try`      | ✅         | output cvars | —                       |
| `cmake_op` | ⚠️ partial | output cvars | —                       |
| `cond`     | ✅         | —            | —                       |
| `dir`      | ✅         | —            | —                       |

### Test infrastructure

- **935 unit tests** (`dune test`) — incl. the surface track (lexer, parser,
  emit-bridge oracle, co-truth locks, grammar freshness) and the per-theory
  check/compile suites
- **108 equivalence/semantic checks** (35 structural + 12 CMakeOnly + 61 RunCMake)
- **cmake ground-truth probes** — `python3 test/test_deref_probes.py` (deref
  semantics, not in `dune test`)
- **12 end-to-end tutorial steps** (generate → configure → build → run)
- **No CI** — all tests are local-only

## Current TODO

Numbers are stable (never renumbered). Priority order tracks `doc/project_overview.md`.

### Implementation (code-ready)

| ID  | Title                          | Description                                  |
| --- | ------------------------------ | -------------------------------------------- |
| ✅   | Name binding (wellform) pass   | Whole-program cvar/target def-use check      |
| —   | Yelu CI                        | Build + test on push                         |
| Y2  | Option combination enumeration | 2^n boolean combos for step4+, File API diff |
| Y5  | File API cache-v2 diff         | Extend oracle beyond codemodel-v2            |
| Y12 | Cmake-layer test mirroring     | Sync cmake PP tests with yelu coverage       |

### Design (before coding)

| ID  | Title                         | Description                                                                                                                                                                                                                                                        |
| --- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Y6  | Semantics hardest to preserve | Genex, policy stack, find_package search                                                                                                                                                                                                                           |
| Y7  | Cache-sensitivity annotations | `Cache_breaking                                                                                                                                                                                                                                                    | Cache_safe | Cache_partial` |
| Y11 | Policy-aware compiler         | Auto-emit policy preamble per construct                                                                                                                                                                                                                            |
| Y13 | Persistent value primitive    | `@cached` with content-addressed store                                                                                                                                                                                                                             |
| Y14 | Reserved keyword validation   | ⚠️ partial — enum-constructor shadowing is a **fatal** reject (`Yc_wellform.check_enum_shadow`, `set public := …` → error); broader cmake-keyword clashes still open |
| Y15 | Binding feature library       | Design space of binding mechanisms — lexical vs global, immutable vs mutable, expression vs statement, name-as-syntax vs name-as-data. Current: `let` (lexical/immutable/expression) + `set` (global/mutable/statement). Future: named choices selectable per pack |
| Y16 | Real-world cmake rewrite      | Rewrite z3/llvm/torch build in yelu, prove structural equivalence. Reframed 2026-06-04 as gradual hybrid adoption — see [doc/yelu_cmake/hybrid_strategy.md](doc/yelu_cmake/hybrid_strategy.md). |
| Y17 | Types on yelu_cmake           | Post-retirement: retrofit a fresh typing pass once `yelu_cmake ↔ Lang_cmake` and `yelu_cmake ↔ yelu_cmake_normal` are stable. Replaces the abandoned R7 "carry production checker over" plan — the theory split gives type design real semantic ground (namespace separation, set-once vs mutable, identity per theory) instead of the shallow per-fragment Stage_typecheck. |
| Y18 | First-class object value      | Promote Pos3's parser-local `cmake_entity` (`Target`/`Source`/`Cache`/`Test`/`Install`/`Directory`/`Global`) to a real value class — operations per kind, value flow (let/args/iterands), eval semantics, wellform integration, multi-entity calls, UFCS `x.f y` ≡ `f x y` for object-method syntax, yc vs ycn placement. Full design: [doc/lang/object_value_design.md](doc/lang/object_value_design.md). Tied to Y15 / Y17 / record literal. |

### Research (likely papers/material)

| ID  | Title                   | Description                                     |
| --- | ----------------------- | ----------------------------------------------- |
| Y3  | Z3 symbolic equivalence | Prove equivalence for all boolean-option inputs |
| Y4  | E-graph investigation   | Equality saturation over state-transformers     |
| Y8  | Multi-stage core        | Quote/splice staging across compile/configure   |

### Done

Y1, Y9, Y10 — see `doc/worklog/worklog_2026_04.md`.

---

## Design Vision

See [doc/manifesto.md](doc/manifesto.md) for the full thesis, motivation,
and layered argument. TL;DR: low-entropy composable language for human+model
configuration generation with verifier feedback. cmake is the first specimen.

---

## Gotchas

- **`open Base` shadows stdlib**: `result`, `prefix`, `id`, `append` are shadowed — rename
  in pattern matches.
- **`let`-bindings inside Angstrom combinators run at module init, not parse time.**
  `p *> (let buf = Buffer.create 64 in ...)` creates `buf` once when the combinator
  value is defined, not per-parse. Use module-level `let buf = ...` with explicit
  `return () >>= fun () -> Buffer.clear buf; ...` at parse time.
- **`Buffer.clear` in Angstrom combinators.** `Buffer.clear buf; parser` runs the clear
  at module init (when the combinator value is constructed), not at parse time. Must wrap:
  `return () >>= fun () -> Buffer.clear buf; parser`. Same applies to any impure
  initialization inside a parser combinator.
- **NEVER use sed or python on OCaml source.** Use the `Edit` tool exclusively. sed cannot
  distinguish match-case scope, let/in boundaries, or which `| _ -> None` is the intended
  anchor. Append commands match multiple locations, line numbers drift, and one bad deletion
  can silently remove adjacent code. `git checkout` recovery costs hours. Edit → build →
  diff → commit after each working tier.
- **OCaml LSP stale diagnostics**: Cross-module edits show false errors until `dune build`.
  ocamllsp reads compiled `.cmi` files. Do not re-attempt edits based on LSP errors.
- **Catch-all ordering in large match expressions**: `| e -> ...` must come LAST after all
  specialized patterns. Putting it first makes everything below unreachable — the compiler
  warns with `redundant-case` but doesn't error.
- **`Fmt.sp` / `Fmt.cut` box sensitivity**: Break *hints* whose behavior depends on the
  enclosing box type (vbox: always break, hovbox: break on overflow, hbox: never break).
  At top level (no box), hints always break. Test output carefully when changing printers.
- **`@.` resets the formatter**: In `lang_cmake_pp.ml`, `@.` calls `pp_print_newline` which
  closes all open boxes. Use `pp_force_newline` in `list_br` instead of `Fmt.cut` after `@.`.
- **`Langs.` → `Yelu_langs.`**: All modules use the `Yelu_langs` library name. The old
  `Langs.` prefix no longer works.
- **`vendor/cmake` is a symlink**: Points to `/home/red/code/contrib/cmake-all/cmake`
  (cmake 4.3 dev). Not a submodule — do not re-add it as one.
- **`vendor/cmake-tutorial` is external**: Not checked in. The cmake tutorial v1 reference
  files live here. Must be set up separately (clone from cmake source).
- **cmake vs shell string semantics**: cmake lists are semicolon-joined strings; shell
  uses space-separated arrays. cmake `if(FOO)` implicitly dereferences FOO — a footgun
  yelu should compile away. Keep `;`-list conflation as a compiler-internal detail.
- **`function()` vs `macro()` semantics**: `macro()` is textual substitution with no scope
  (like C `#define`). `function()` creates a new variable scope. OCaml already provides
  parameterization — cmake `function()` is only needed when generated cmake is consumed
  by downstream projects.
- **Tutorial v1 vs v2**: `vendor/cmake-tutorial/step{1-12}/` is v1 (CMake 3.20) — what
  the OCaml step files target. `vendor/cmake/Help/guide/tutorial/` is v2 (CMake 3.23+).
  Step numbering does NOT map 1:1.
- **cmake ANSI codes in script output**: `cmake_runner.ml` sets `CLICOLOR_FORCE=0`.
  The `message/newline` RunCMake compat test remains blocked on some configurations.
- **cmake runtime is 4.3.1**: Both runtime and vendor source are cmake 4.3.1 (Kitware apt).
  Previously 3.28.3; upgrading unblocked `cmake_path GET`, `message/newline`,
  `string/RegexEmptyMatch`, and `get_filename_component KnownComponents`.
- **Git worktree paths are relative to source repo, not yelu cwd.**
  `git -C <repo> worktree add --detach <path> HEAD` creates the worktree at
  `<repo>/<path>`, not at `<cwd>/<path>`. Always resolve to absolute:
  `realpath _out/fmt/hybrid/source` before passing to `git worktree add`.
  Similarly, `git worktree remove` must use the absolute path.
- **`git worktree remove` cleans metadata; `rm -rf` does not.**
  Deleted worktrees leave stale entries in `<repo>/.git/worktrees/`.
  Always `git worktree remove --force` (or `git worktree prune` as fallback)
  before `rm -rf` when cleaning up. The stale metadata prevents re-creating
  a worktree at the same path.
- **`Stdlib.Filename.dirname "foo"` returns `"."` not `""`.**
  For root-level files (no directory prefix), `dirname` returns `"."`.
  `Stdlib.Filename.concat "." "bar"` → `"./bar"` — the `./` prefix breaks
  downstream path handling. Check for `"."` and use the bare filename.
- **`mkdirp` must skip `"."`** — `Sys.file_exists "."` returns true, but
  `Unix.mkdir "."` fails with EEXIST. Guard with `String.equal path "."`.
- **Symlink-mirror leaves stale real directories under `_out/`.**
  The old `build_hybrid_tree` created real directories for ancestors of
  spliced files (`test/`, `support/`). The git-worktree replacement needs
  a full `rm -rf` before checkout to avoid conflicts.
- **Co-truth lock tests** assert two independently-maintained sources agree
  (no baked-in golden), so drift is a build failure, not a silent bug. The
  chain `Yelu_lexer.constr_names` → `Yc_manifest` → `Yc_tmgrammar` rules →
  committed `yc.tmLanguage.json` is fully locked. **After changing
  `constr_names` (or any manifest vocabulary), regenerate the grammar with
  `dune promote`** (the `test/test-tmgrammar` `(diff)` rule fails `dune test`
  until you do). Same family as the emit-bridge oracle and the fmt matrix.
- **Surface changes are blind to the emit oracle.** `$foo`/quote/enum-
  constructor canonicalization all keep emit byte-identical (lexer normalizes
  to the existing token; formatter only changes display), so the emit-bridge
  + matrix can't see them — each needs its own surface-level regression test
  (in `test_yelu_lexer` / `test_yc_cst_bridge`). The fmt CLI double-newline
  bug hid the same way (tests called `Yc_driver.format`, not the CLI).
- Remote: `github.com/yelu-lang/yelu-lang`.

## Handoff Workflow

Before ending a session, update this file with:

1. **Build & Run** — new make targets, changed commands
2. **Key Files** — new important files and their purpose
3. **Architecture** — design changes, new modules, new patterns
4. **Current TODO** — items completed, items started, new items
5. **Gotchas** — new traps, workarounds discovered

Update `doc/project_overview.md` if the project-level audit changes (new
theories, major test count changes, gap closures). Commit the result.
