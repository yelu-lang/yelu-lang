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

| File                                     | Purpose                                                       |
| ---------------------------------------- | ------------------------------------------------------------- |
| `src/langs/cmake/lang_cmake.ml`          | CMake AST — all 133 commands, stringly-typed                   |
| `src/langs/cmake/lang_cmake_pp.ml`       | Pretty printer (AST → CMake text)                              |
| `src/langs/cmake/lang_cmake_utils.ml`    | Ergonomic AST constructors                                     |

### yelu layer (typed surface language)

| File                                     | Purpose                                                       |
| ---------------------------------------- | ------------------------------------------------------------- |
| `src/langs/yelu/lang_yelu.ml`            | Core: `LANG_TYPES`, `Make_stmt` functor bundle                 |
| `src/langs/yelu/lang_yelu_type.ml`       | Type universe, `checking_stage`, `CHECKER_BASE`                |
| `src/langs/yelu/lang_yelu_cmake.ml`      | Cmake-pack: `yelu_stmt`, `Cmake_check`, 14 theory instantiations |
| `src/langs/yelu/lang_yelu_compile.ml`    | Compiler: type erasure yelu → cmake AST (`stage = Stage_lower`)|
| `src/langs/yelu/lang_yelu_utils.ml`      | Ergonomic constructors for building yelu AST                   |
| `src/langs/yelu/lang_yelu_wellform.ml`   | Wellform pass: whole-program cvar/target name binding check     |

### Fragments (per-theory functors, `src/langs/yelu/fragments/`)

Each fragment defines a `Make_*_op (T)` / `Make_*_check (T)` functor pair over `LANG_TYPES`.
All 14 `Make_*_check` modules expose `let stage = Stage_typecheck`, enforced by `CHECKER_BASE`.

| File                       | Lines | Theory          |
| -------------------------- | ----- | --------------- |
| `lang_yelu_var.ml`         | 44    | Variable set/unset/cache |
| `lang_yelu_target.ml`      | 164   | Target (add_library, link, compile options) |
| `lang_yelu_string.ml`      | 136   | String operations |
| `lang_yelu_path.ml`        | 135   | Path operations   |
| `lang_yelu_file.ml`        | 110   | File I/O          |
| `lang_yelu_cond.ml`        | 72    | Conditions        |
| `lang_yelu_list.ml`        | 67    | List operations   |
| `lang_yelu_property.ml`    | 66    | Property (get/set/define) |
| `lang_yelu_install.ml`     | 65    | Install rules     |
| `lang_yelu_try.ml`         | 65    | try_compile/run   |
| `lang_yelu_find.ml`        | 81    | find_package/library/path |
| `lang_yelu_cmake_op.ml`    | 82    | cmake_language, math, execute_process |
| `lang_yelu_dir.ml`         | 37    | Directory ops     |
| `lang_yelu_test.ml`        | 20    | Test ops          |
| `lang_yelu_genex.ml`       | 50    | Generator expressions |

### Step files (tutorial + CMakeOnly generators)

| Directory                  | Count | Purpose                                    |
| -------------------------- | ----- | ------------------------------------------ |
| `src/bin/cmake/v1/`        | 25    | CMake tutorial v1 reference generators     |
| `src/bin/cmake/v2/`        | 11    | CMake tutorial v2 reference generators     |
| `src/bin/yelu/v1/`         | 25    | Same tutorials in yelu DSL                 |
| `src/bin/yelu/v2/`         | 11    | Same tutorials in yelu DSL                 |
| `src/bin/yelu/` (top)      | 13    | CMakeOnly test suite generators            |
| `src/bin/yelu/common/`     | 1     | Shared step utilities (`step_common`)      |

### Tests

| File                                     | Tests | Purpose                                     |
| ---------------------------------------- | ----- | ------------------------------------------- |
| `test/test-cmake/test_cmake_pp.ml`       | 70    | cmake pretty-printer                        |
| `test/test-yelu/test_yelu_compile.ml`    | 194   | yelu → cmake compilation                    |
| `test/test-yelu/test_yelu_check.ml`      | 58    | per-theory type checking (17) + wellform name binding (41)|
| `test/test-runcmake/`                    | 37    | cmake -P compat + yelu scripts              |
| `test/test-file-api/`                    | —     | codemodel-v2 JSON diff                      |

### Documentation

| File                                    | Purpose                                          |
| --------------------------------------- | ------------------------------------------------ |
| `doc/yelu_manifesto.md`                 | Project manifesto: thesis, falsifiability, approach |
| `doc/yelu_project_overview.md`          | Full project audit: code, tests, gaps, TODOs      |
| `doc/yelu_typed_design.md`             | Type system, compositional checking architecture  |
| `doc/yelu_lang_design.md`              | Language design: staging, types, surface syntax   |
| `doc/yelu_lang_coverage.md`            | cmake command coverage, 4-tier roadmap            |
| `doc/yelu_concrete_syntax_parser.md`   | Menhir grammar design for concrete syntax         |
| `doc/cmake_painpoints.md`              | 27 documented cmake pain points                   |
| `doc/cmake_comparison.md`              | cmake PL properties, equivalence levels           |
| `doc/cmake_policy.md`                  | cmake policy system, CMP* history                 |
| `doc/cmake_genex.md`                   | Generator expressions design                      |
| `doc/cmake_script.md`                  | cmake -P script vs configure mode                 |
| `doc/cmake_equiv_research.md`          | Z3 / e-graph equivalence research prompts         |
| `doc/yelu_beyond.md`                   | Multi-pack architecture, AI language stacks       |
| `doc/yelu_research_framing.md`         | Benchmark design, contamination-aware eval        |
| `doc/yelu_infra_test.md`               | Test harness, dune aliases, gotchas               |
| `doc/worklog_2026_04.md`               | Completed items (Y1, Y9, Y10)                     |

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

| Stage           | What it checks                                                     | Status                   |
| --------------- | ------------------------------------------------------------------ | ------------------------ |
| `typecheck`     | Expression-level type constraints — per-theory, per-statement      | ✅ 14 theories complete  |
| `wellform`      | Name binding: cvar/target declarations and cross-theory ref checks | ✅ done (2026-05-04)     |
| `effect`        | cmake execution-mode constraints                                   | ⏳ not started           |
| `lower`         | Structural validity during AST → cmake                             | ⚠️ partial               |
| `configure`     | cmake itself: REQUIRED, math, policy                               | ✅ via RunCMake compat   |

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

### Done this session (2026-05-04)

- **Wellform pass**: Whole-program name binding check (`lang_yelu_wellform.ml`).
  Checks that every cvar/target reference has a prior declaration. 41 new tests
  (26 positive, 15 negative). Handles: builtin cvar exemption, `Yis_defined`/
  `Yis_target` exemption, branch unioning, loop/function/macro scoping, compile-time
  binding resolution via `Ylet`.

### Done earlier (2026-04-30 to 2026-05-04)

- **`tc_name` unified type**: Replaced `yelu_cvar`/`yelu_target`/`Ycs_name` with
  single `tc_name = { ns : cmake_namespace; name }` across all 14 theories + compiler.
- **Fragment split**: `lang_yelu_state.ml` → `lang_yelu_var.ml` + `lang_yelu_property.ml`
  (variable namespace vs property namespace).
- **`checking_stage` type**: Iterated through three revisions —
  `Stage_check/scope/type/lower` → `Stage_static/effect/lower` →
  `Stage_typecheck/wellform/effect/lower`. Final design classifies by semantic
  property rather than pass structure (per-stmt vs whole-program is an algorithm
  choice, not a stage boundary).
- **`CHECKER_BASE` enforcement**: Module signature + first-class module list ensures
  every theory declares its stage. New fragments that forget `stage` fail at compile time.
- **`yelu_typed_design.md`**: Rewrote "Checking stages" → "Compositional checking
  architecture" with theory coverage table.
- **`yelu_project_overview.md`**: Full project audit — code inventory, test counts,
  14-theory analysis table, gaps, implementation queue.
- **`yelu_manifesto.md`**: Project manifesto — thesis, six sub-properties, falsifiability,
  related work, anti-scope.
- **Extraction from tola**: Standalone at `/home/red/code/research/yelu`. Own
  `dune-project`, opam file, Makefile updated (no `yelu/` path prefix), vendor
  symlinks preserved, memory + settings migrated, git remote set to
  `github.com/yelu-lang/yelu-lang`. Clean build, 194/194 tests pass.
- **Tola cleanup**: CLAUDE.md updated to point to new location, `yelu/vendor/yelu-lang`
  submodule removed from `.gitmodules`, `MEMORY.md` cleaned of yelu-specific sections.

### 14 theories status

| Theory       | Typecheck        | Declares      | References cross-theory     |
| ------------ | ---------------- | ------------- | --------------------------- |
| `var`        | ✅               | cvars         | —                           |
| `target`     | ✅               | targets       | target names                |
| `install`    | ✅               | —             | declared targets            |
| `test`       | ⚠️ minimal       | —             | declared targets            |
| `property`   | ✗ stub           | output cvars  | target names                |
| `string`     | ✅               | output cvars  | —                           |
| `file`       | ✅               | output cvars  | —                           |
| `path`       | ✅               | output cvars  | —                           |
| `list`       | ✅               | output cvars  | cvars must exist            |
| `find`       | ⚠️ partial       | output cvars  | —                           |
| `try`        | ✅               | output cvars  | —                           |
| `cmake_op`   | ⚠️ partial       | output cvars  | —                           |
| `cond`       | ✅               | —             | —                           |
| `dir`        | ✅               | —             | —                           |

### Test infrastructure

- **324 unit tests** (72 cmake PP + 194 yelu compile + 58 yelu check)
- **108 equivalence/semantic checks** (35 structural + 12 CMakeOnly + 61 RunCMake)
- **12 end-to-end tutorial steps** (generate → configure → build → run)
- **No CI** — all tests are local-only

## Current TODO

Numbers are stable (never renumbered). Priority order tracks `yelu_project_overview.md`.

### Implementation (code-ready)

| ID   | Title                                   | Description                                  |
| ---- | --------------------------------------- | -------------------------------------------- |
| ✅    | Name binding (wellform) pass            | Whole-program cvar/target def-use check      |
| —    | Yelu CI                                 | Build + test on push                         |
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
| Y15  | Binding feature library                 | Design space of binding mechanisms — lexical vs global, immutable vs mutable, expression vs statement, name-as-syntax vs name-as-data. Current: `let` (lexical/immutable/expression) + `set` (global/mutable/statement). Future: named choices selectable per pack |

### Research (likely papers/material)

| ID   | Title                                   | Description                                  |
| ---- | --------------------------------------- | -------------------------------------------- |
| Y3   | Z3 symbolic equivalence                 | Prove equivalence for all boolean-option inputs |
| Y4   | E-graph investigation                   | Equality saturation over state-transformers  |
| Y8   | Multi-stage core                        | Quote/splice staging across compile/configure |

### Done

Y1, Y9, Y10 — see `doc/worklog_2026_04.md`.

---

## Design Vision

**Project statement**: Yelu is a controlled front-end for studying whether regular
syntax, explicit namespaces, canonical forms, and local verification improve
model-driven generation and repair for configuration languages, with cmake as the
first target and equivalence oracle.

**What yelu is not**: a better template language, cmake syntax sugar, or a build system.

**What yelu is**: a programmable configuration shell language — a staged DSL that
provides universal programmability and local verification for target config languages
(cmake first; json/yaml/nix are future packs).

**The core design property: low entropy.** The unifying language-level property is
low entropy in names, forms, defaults, and error locations — minimize surface
diversity so there's one way to say a thing, few hidden defaults, few overloaded
names, few stringly-typed dispatch points. Concrete sub-properties (in priority
order for machine-driven generation/repair):

1. Closed-world names and typed slots (no silent shadowing across namespaces)
2. Local, structured failure (faults surface at their origin)
3. Canonical surface forms (canonicalizer collapses equivalent programs)
4. Explicit phase boundaries (compile / configure / build / install are named)
5. Regular grammar (one syntactic form per concept)
6. Searchable type/schema surfaces (type info is first-class AST data)
7. Deterministic operational semantics

**Primary optimization target: human-plus-model production with verifier feedback.**
A model generates/repairs/navigates the language under verifier feedback, and a
human reviews and directs. The language is optimized for this loop — not for
unadorned model consumption, and not for unadorned human authoring.

**Research question**: do languages with low syntactic and semantic entropy plus
strong local verification produce better model-driven generation and repair?

**Falsifiability** (from `doc/yelu_manifesto.md`):
1. LLMs using yelu don't produce fewer errors vs raw cmake on matched tasks
2. Error classes caught by yelu's checker are a strict subset of cmake's own errors
3. Adding a new theory requires modifying existing theories' checkers
4. A second target pack requires redesigning `LANG_TYPES` or `checking_stage`

**Generalization beyond cmake**: cmake is the specimen, not the thesis. The two-layer
architecture is designed to generalize — a json-pack or nix-pack would reuse the core
while targeting different semantics.

---

## Gotchas

- **`open Base` shadows stdlib**: `result`, `prefix`, `id`, `append` are shadowed — rename
  in pattern matches.
- **OCaml LSP stale diagnostics**: Cross-module edits show false errors until dune rebuilds.
- **Catch-all ordering in large match expressions**: `| e -> ...` must come LAST after all
  specialized patterns. Putting it first makes everything below unreachable — the compiler
  warns with `redundant-case` but doesn't error. Check this in wellform, typechecker, and
  compiler whenever adding new expression or statement constructors.
  ocamllsp reads compiled `.cmi` files directly. Always verify with `dune build` at the end.
  Do not re-attempt edits in response to stale LSP errors mid-turn.
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
- **Project is standalone since 2026-05-04**: Extracted from `/home/red/code/research/tola/yelu/`.
  The original tola repo still has the `yelu/` directory for git history but yelu development
  now happens here. Remote: `github.com/yelu-lang/yelu-lang` (no push yet).

## Handoff Workflow

Before ending a session, update this file with:

1. **Build & Run** — new make targets, changed commands
2. **Key Files** — new important files and their purpose
3. **Architecture** — design changes, new modules, new patterns
4. **Current TODO** — items completed, items started, new items
5. **Gotchas** — new traps, workarounds discovered

Update `doc/yelu_project_overview.md` if the project-level audit changes (new
theories, major test count changes, gap closures). Commit the result.
