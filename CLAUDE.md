# Claude Code — Yelu Project Guide

> **Scope**: Yelu is now a standalone project at `/home/red/code/research/yelu`
> (extracted from tola monorepo on 2026-05-04). Remote: `github.com/yelu-lang/yelu-lang`.

## Build & Run

All commands run from the yelu repo root (`dune-project` lives here).

```sh
dune build                                      # everything
dune build src/langs/ src/bin/cmake/v1/         # cmake layer only
dune build src/langs/ src/bin/yelu/             # yelu layer only
dune test                                       # all unit tests (281 tests)
```

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

### cmake layer (stringly-typed AST)

| File                                  | Purpose                                      |
| ------------------------------------- | -------------------------------------------- |
| `src/langs/cmake/lang_cmake.ml`       | CMake AST — all 133 commands, stringly-typed |
| `src/langs/cmake/lang_cmake_pp.ml`    | Pretty printer (AST → CMake text)            |
| `src/langs/cmake/lang_cmake_utils.ml` | Ergonomic AST constructors                   |

### yelu layer (typed surface language)

| File                                   | Purpose                                                          |
| -------------------------------------- | ---------------------------------------------------------------- |
| `src/langs/yelu/lang_yelu.ml`          | Core: `LANG_TYPES`, `Make_stmt` functor bundle                   |
| `src/langs/yelu/lang_yelu_type.ml`     | Type universe, `checking_stage`, `CHECKER_BASE`                  |
| `src/langs/yelu/lang_yelu_cmake.ml`    | Cmake-pack: `yelu_stmt`, `Cmake_check`, 14 theory instantiations |
| `src/langs/yelu/lang_yelu_compile.ml`  | Compiler: type erasure yelu → cmake AST (`stage = Stage_lower`)  |
| `src/langs/yelu/lang_yelu_utils.ml`    | Ergonomic constructors for building yelu AST                     |
| `src/langs/yelu/lang_yelu_wellform.ml` | Wellform pass: whole-program cvar/target name binding check      |

### Fragments (per-theory functors, `src/langs/yelu/fragments/`)

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

### Step files (tutorial + CMakeOnly generators)

| Directory              | Count | Purpose                                |
| ---------------------- | ----- | -------------------------------------- |
| `src/bin/cmake/v1/`    | 25    | CMake tutorial v1 reference generators |
| `src/bin/cmake/v2/`    | 11    | CMake tutorial v2 reference generators |
| `src/bin/yelu/v1/`     | 25    | Same tutorials in yelu DSL             |
| `src/bin/yelu/v2/`     | 11    | Same tutorials in yelu DSL             |
| `src/bin/yelu/` (top)  | 13    | CMakeOnly test suite generators        |
| `src/bin/yelu/common/` | 1     | Shared step utilities (`step_common`)  |

### Tests

| File                                       | Tests | Purpose                                                    |
| ------------------------------------------ | ----- | ---------------------------------------------------------- |
| `test/test-cmake/test_cmake_pp.ml`         | 72    | cmake pretty-printer                                       |
| `test/test-yelu/test_yelu_compile.ml`      | 194   | yelu → cmake compilation                                   |
| `test/test-yelu/test_yelu_check.ml`        | 57    | per-theory type checking + wellform name binding           |
| `test/test-yelu/test_yelu_lexer.ml`        | 25    | concrete-syntax lexer                                      |
| `test/test-yelu/test_yelu_parse.ml`        | 170   | concrete-syntax parser                                     |
| `test/test-yelu/test_yelu_tiny_bridge.ml`  | 43    | production yelu_cmake AST → tiny Yelu1                     |
| `test/test-yelu/test_yelu_tiny_emit.ml`    | 3     | tiny IR → cmake text                                       |
| `test/test-yelu/test_yelu_tiny_lift_lower.ml` | 65 | Yelu1 ↔ Yelu2 roundtrip                                    |
| `test/test-yelu/test_yelu_tiny_steps.ml`   | 19    | tutorial v1 step1–step12 + 8_table + 11_config + ctest     |
| `test/test-yelu/test_yelu_tiny_function.ml`| 14    | F2: dynamic scope / shallow binding                        |
| `test/test-runcmake/test_yelu_tiny_cmake.ml`| 40   | tiny lowerings configure through real cmake                |
| `test/test-runcmake/` (other)              | 37    | cmake -P compat + yelu scripts                             |
| `test/test-file-api/`                      | —     | codemodel-v2 JSON diff                                     |

Total unit: 655. Total cmake-backed: 40.

### Documentation

| File                                 | Purpose                                             |
| ------------------------------------ | --------------------------------------------------- |
| `doc/yelu_manifesto.md`              | Project manifesto: thesis, falsifiability, approach |
| `doc/yelu_project_overview.md`       | Full project audit: code, tests, gaps, TODOs        |
| `doc/yelu_typed_design.md`           | Type system, compositional checking architecture    |
| `doc/yelu_lang_design.md`            | Language design: staging, types, surface syntax     |
| `doc/yelu_lang_coverage.md`          | cmake command coverage, 4-tier roadmap              |
| `doc/yelu_concrete_syntax_parser.md` | Menhir grammar design for concrete syntax           |
| `doc/cmake_painpoints.md`            | 27 documented cmake pain points                     |
| `doc/cmake_comparison.md`            | cmake PL properties, equivalence levels             |
| `doc/cmake_policy.md`                | cmake policy system, CMP* history                   |
| `doc/cmake_genex.md`                 | Generator expressions design                        |
| `doc/cmake_script.md`                | cmake -P script vs configure mode                   |
| `doc/cmake_equiv_research.md`        | Z3 / e-graph equivalence research prompts           |
| `doc/yelu_beyond.md`                 | Multi-pack architecture, AI language stacks         |
| `doc/yelu_research_framing.md`       | Benchmark design, contamination-aware eval          |
| `doc/yelu_infra_test.md`             | Test harness, dune aliases, gotchas                 |
| `doc/worklog_2026_04.md`             | Completed items (Y1, Y9, Y10)                       |
| `doc/worklog_2026_05.md`             | yelu_tiny harness Tier A–F (Bar #1 + Bar #2)        |
| `doc/yelu_theory_composition_design.md` | Durable design notes for yelu_tiny harness       |
| `THEORY_COMPOSITION_PLAN.md`         | Short-lived tracker for yelu_tiny TODO              |

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

### Parallel harness: yelu_tiny

A separate composition harness in `src/langs/yelu_tiny/` re-shapes the
production AST into two axles (Yelu1 = tiny core + cmake-shaped surfaces;
Yelu2 = tiny core + idealized theories) and bridges from production
`yelu_cmake` AST → Yelu1 → cmake. Each fragment provides a matched
`yelu_theory_*` / `yelu_surface_cmake_*` pair. As of 2026-05-10:
v1 step1–step12 all bridge through tiny; six configure through real cmake.
Details in `doc/worklog_2026_05.md` and `THEORY_COMPOSITION_PLAN.md`.

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

See [doc/yelu_typed_design.md](doc/yelu_typed_design.md) for the full design.

## Current State

> Session history → [doc/worklog_2026_04.md](doc/worklog_2026_04.md).
> Full audit → [doc/yelu_project_overview.md](doc/yelu_project_overview.md).

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

- **408 unit tests** (72 cmake PP + 194 yelu compile + 57 yelu check + 20 lexer + 65 parser)
- **108 equivalence/semantic checks** (35 structural + 12 CMakeOnly + 61 RunCMake)
- **12 end-to-end tutorial steps** (generate → configure → build → run)
- **No CI** — all tests are local-only

## Current TODO

Numbers are stable (never renumbered). Priority order tracks `yelu_project_overview.md`.

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
| Y14 | Reserved keyword validation   | Enumerate cmake keywords, warn on clashes                                                                                                                                                                                                                          |
| Y15 | Binding feature library       | Design space of binding mechanisms — lexical vs global, immutable vs mutable, expression vs statement, name-as-syntax vs name-as-data. Current: `let` (lexical/immutable/expression) + `set` (global/mutable/statement). Future: named choices selectable per pack |
| Y16 | Real-world cmake rewrite      | Rewrite z3/llvm/torch build in yelu, prove structural equivalence. Optimize yelu_cmake, prove optimized ≡ original |

### Research (likely papers/material)

| ID  | Title                   | Description                                     |
| --- | ----------------------- | ----------------------------------------------- |
| Y3  | Z3 symbolic equivalence | Prove equivalence for all boolean-option inputs |
| Y4  | E-graph investigation   | Equality saturation over state-transformers     |
| Y8  | Multi-stage core        | Quote/splice staging across compile/configure   |

### Done

Y1, Y9, Y10 — see `doc/worklog_2026_04.md`.

---

## Design Vision

See [doc/yelu_manifesto.md](doc/yelu_manifesto.md) for the full thesis, motivation,
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
- Remote: `github.com/yelu-lang/yelu-lang`.

## Handoff Workflow

Before ending a session, update this file with:

1. **Build & Run** — new make targets, changed commands
2. **Key Files** — new important files and their purpose
3. **Architecture** — design changes, new modules, new patterns
4. **Current TODO** — items completed, items started, new items
5. **Gotchas** — new traps, workarounds discovered

Update `doc/yelu_project_overview.md` if the project-level audit changes (new
theories, major test count changes, gap closures). Commit the result.
