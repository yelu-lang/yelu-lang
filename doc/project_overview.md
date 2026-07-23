# Yelu — Project Overview

> Last full pass: 2026-07-22. The 2026-06 surface track (no-ALL_CAPS `~`-half +
> labeled-only Step 2, property unification, Pos3 entity prototype, `:=`
> sugar, LSP), the 2026-06 syntax audit closure, the Tier (b) parser
> retirement, and the 2026-07-20..22 coverage-lock / doc-consolidation work are all
> reflected in the body below. Current in-flight work lives in
> [`status.md`](status.md).

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

- 14 cmake-faithful fragments: `target`, `string`, `path`, `file`, `list`,
  `find`, `install`, `test`, `try`, `if`, `dir`, `property`, `cmake_op`,
  `store` (var ops live in the core, not a fragment).
- 16 normalized fragments including the cmake-faithful set plus a small
  general-purpose subset (`bool`, `int`) that is theory-agnostic and a candidate
  for future re-use across packs.

Forward architectural plan (theory-fragment split) at
[`plan.md`](yelu_cmake_normal/typing/plan.md).

### Layered checking

| Stage       | What it checks                                                     | Status                |
| ----------- | ------------------------------------------------------------------ | --------------------- |
| `typecheck` | Expression-level type constraints — per-theory, per-statement      | retired with Y17 pending |
| `wellform`  | Surface-level static analysis — six independent checks (see below) | ✅ shipped, see surface_lsp_framework.md §7.5 |
| `effect`    | cmake execution-mode constraints                                   | ⏳ not started        |
| `lower`     | Structural validity during AST → cmake                             | ⚠️ partial            |
| `configure` | cmake itself: REQUIRED, math, policy                               | ✅ via RunCMake compat |

**Wellform** is now the diagnostic engine all surfaces share
([`Yc_wellform.check_all`](../src/langs/yelu/yc_wellform.ml) on `expr`,
[`Yc_wellform.check_cst`](../src/langs/yelu/yc_wellform.ml) on the CST). Six checks:

| Check                        | Source     | Severity                | Catches                                                                |
| ---------------------------- | ---------- | ----------------------- | ---------------------------------------------------------------------- |
| `Reserved_name`              | expr       | warning                 | `EVar` collides with a reserved keyword or typed primitive             |
| `Apply_shadows_primitive`    | expr       | warning                 | `yc_apply "string_concat"` escapes a typed yc API                      |
| `Enum_shadow` (Y14)          | expr       | **fatal**               | `set public := …` — variable shadows an enum constructor               |
| `Raw_cmake_escape`           | expr       | info                    | `yc_raw '…'` use, surfaced so it isn't silent                          |
| `Positional_form` (Step 2)   | expr       | **fatal**               | A labeled-only command written in cmake's positional keyword form      |
| `Unknown_command`            | expr       | fatal (closed-world) / warning (open-world) | Command name neither in `command_names` nor declared as `function`/`macro` in-file. Closed-world: file has no opening construct (`include`/`find_package`/`add_subdirectory`/`cmake_call`/dynamic fun-name) |
| `Function_def_typo`          | CST shape  | **fatal**               | `IDENT args (block)` adjacent to standalone block — only valid as fun-def; flags typo'd `fun`/`function`/`macro` keyword regardless of open/closed world |

Surfacing is uniform across compile / fmt / LSP / corpus-gate per the
contract in [`driver.md`](framework/driver.md) §6.5: fatal
findings exit the per-file compile, refuse format, become Error
diagnostics in the LSP. Warnings appear in stderr / Problems panel but
don't block.

The earlier per-fragment `Stage_typecheck` pass was retired alongside
the legacy production AST (commits up to E1, 2026-05-14). Y17 — a fresh
typing pass over the post-retirement `yelu_cmake` / `yelu_cmake_normal`
IR — is the replacement; tracked in
[`status.md`](status.md) "Open work".

## Current State

### Code layout

| Layer                                                  | Notes                                                     |
| ------------------------------------------------------ | --------------------------------------------------------- |
| `src/langs/cmake/`                                     | Stringly-typed cmake AST + pretty-printer (`Lang_cmake.exp`, `Lang_cmake_pp`). |
| `src/langs/yelu/`                                      | Production: `yelu_cmake` + `yelu_cmake_normal` + parser + emit. |
| `src/langs/yelu/fragments/`                            | 30 per-theory fragments (14 cmake-faithful + 16 normalized). |
| `src/langs/yelu_legacy/`                               | Retired reference; excluded from the `yelu_langs` library via `dune` negative-module list. E2 will `git rm` it after Y17. |
| `src/bin/cmake/v1/`, `src/bin/cmake/v2/`, `src/bin/yelu/v1/`, `src/bin/yelu/v2/`, `src/bin/yelu/` | Tutorial step files + CMakeOnly generators. |
| `tool/cmake_text/`                                | Tools that operate on cmake text: parse, reprint, scan, index, oracle. |

### Test infrastructure

| Suite                              | Count    | What it verifies                                              |
| ---------------------------------- | -------: | ------------------------------------------------------------- |
| Unit tests (`dune test`)           | ~1034     | Pretty-printer, compile, parse, eval, lift/lower, steps, surface (lexer / parser / CST / co-truth locks / grammar freshness), per-theory check/compile suites. (The emit-bridge oracle retired with the legacy parser in Tier (b) — once both sides are one path the comparison is a tautology.) |
| **Command-coverage lock** (in `dune test`) | 138 commands | `test_yelu_cmake_parse` records every command its cases exercise and asserts `command_names \ covered = {}`; a command with no parse+emit case fails the build. Added 2026-07-20 after a scan found 15 commands with no test and 5 broken. |
| **Dispatch lock** (in `dune test`) | 138 commands | `test_yc_manifest` asserts every `command_names` entry is owned by a family `_inner` (`Yc_cst_lower.family_of ≠ Fam_generic`) — i.e. none falls through to the raw escape and emits its yc name as bogus cmake. |
| **Command-reference freshness** (in `dune test`) | 1 | committed `doc/yelu_cmake/surface/yc_command_reference.md` must byte-match `yelu command-reference` (generated from the code). Drift fails the build; fix is `dune promote`. |
| **Corpus compile gate** (in `dune test`) | every `.yc` under `probes/fmt` | `yelu compile-corpus probes/fmt` — parse + wellform + emit each file; fails the build on a positional cmake-keyword form, enum-shadow, parse error, or emit crash. Closes the blind spot where `compile main.yc` was byte-identical but discovered helpers (`probes/fmt/test/*/CMakeLists.yc`) had regressed. |
| `make runcmake-yelu`               | 50 / 50  | yelu-generated scripts vs cmake reference output.             |
| `make cmake-only-check`            | 12 / 12  | Structural equivalence for `Tests/CMakeOnly/`.                |
| `make cmake-check-v1`              | 24 / 24  | Tutorial v1 structural-equivalence via gersemi.               |
| `make cmake-check-v2`              | 11 / 11  | Tutorial v2 structural-equivalence via gersemi.               |
| `make file-api-test`               | 12 / 12  | codemodel-v2 JSON diff on tutorial steps.                     |
| `make build-check`                 | 12 / 12  | build-artifact existence + ELF-magic check on tutorial steps. |
| `make build-equiv`                 | 5 / 5    | build ref-cmake vs yc-cmake; compare artifacts / `nm` symbols / runtime / bytes / consume-script. Incl. `fmt`: real `libfmt` **byte-identical** (1000/1000 symbols). Level 7 in [`framework/testing.md`](framework/testing.md). |
| End-to-end (`make step1`–`step12`) | 12       | Generate → configure → build → run.                           |
| Bar #3-lite parse-print round-trip | 740 / 740 (canonical) + 3004 / 3035 (full llvm-project) | tutorial 25/25 + fmt 11/11 + z3 108/108 + llvm/llvm 596/596 = canonical 740. Full llvm-project (3035 files) adds 3004 OK + 1 FORMAT + 30 STRUCT pre-existing. See [`worklog_2026_06.md`](worklog/worklog_2026_06.md). |
| fmt full-project matrix            | 24 / 24 cells × 3 channels | All 11 `.yc` files compile; predicted cache has 0 semantic differences; 29 codemodel keys have 0 differences; CTest definitions including full command args match. See [`fmt/README.md`](../probes/fmt/README.md). |
| tm-grammar co-truth lock           | 1        | `dune promote` round-trip: committed `editors/vscode/yc/syntaxes/yc.tmLanguage.json` byte-matches what `yelu tmgrammar` emits from `Yc_manifest`. Surface-vocabulary drift fails the build. |

`make cmake-commands` has pre-existing cmake build issues (not blocking). The
`ylet chain` case in `test_yelu_compile` is commented out (a TODO, not a live
failure — blocked by the `ylet` blanket `EVar→EString` demotion).

### Project-level milestones

- **Bar #1 — tutorial v1 step1–step12.** ✅ All bridge through `yelu_cmake`;
  all 12 configure through real cmake; 12 file-api JSON diffs match.
- **Bar #2 — every production theory has at least a first slice.** ✅ All 14.
- **Bar #3-lite — parse-print cmake round-trip on z3 + llvm.** ✅ Shipped
  2026-05-15..20. STRUCT=0 / FORMAT=0 across 729 files in tutorial + z3 +
  llvm canonical. Surfaced and fixed 5 production-IR bugs. Audit-ready
  writeup at [`worklog_2026_06.md`](../doc/worklog/worklog_2026_06.md).
  Extended 2026-06-03 to include fmt (11/11 OK) and the full llvm-project
  corpus (3004/3035 OK + 1 FORMAT + 30 STRUCT pre-existing).
- **Cache namespace + `-D` cmd-line input.** ✅ Shipped 2026-06-01.
  `ECmakeSetCache` and `ECmakeOption` now write into `env.cache_vars`
  (separate from `env.frames`); `-D` populates cache before eval so
  `option()` is correctly a NO-OP when the entry exists. Record in
  [`worklog_2026_06.md`](worklog/worklog_2026_06.md)
  (§ "Cache namespace + `-D` cmd-line input — shipped").
- **fmt full-project yelu-cmake probe complete.** ✅ The predictor matrix
  shipped 2026-06-03, all 11 CMake files gained `.yc` equivalents by
  2026-06-08, and the tripled oracle closed the audit on 2026-07-16. Every
  source is guarded by the corpus compile gate; all 24 option cells match in
  cache, File API codemodel, and CTest-definition channels. Closing it required:
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
  Audit-ready writeup at [`README.md`](../probes/fmt/README.md).
- **Surface syntax — no-ALL_CAPS pass (the `~`-half).** ✅ Shipped
  2026-06-04..19. Every cmake keyword arg is now a labeled argument
  (`~flag` / `~label=value` / `~label=[list]` / `~properties={record}`)
  or an explicit `yc_raw` escape. Casing lanes (enum constructors
  leading-cap), `$foo` brace-elision, single-quote canonical strings.
  Empirical cmake ground truth recorded in
  [`painpoints.md`](cmake/painpoints.md) §11. See
  [`worklog_2026_06.md`](worklog/worklog_2026_06.md) "2026-06-19".
- **Surface syntax — Step 2 labeled-only (positional reject).** ✅
  Shipped 2026-06-19. Positional cmake-keyword forms are a **fatal
  compile error** (`Positional_form` wellform finding); the `~label=`
  form is the sole surface. `fmt` is **pass-through** — no
  positional→labeled codemod; a positional file is rejected at compile,
  not silently rewritten. Per-family rollout (install / target /
  property / cmake_op).
- **Property family unified.** ✅ Shipped 2026-06-13..14. `set_property`
  collapsed from 4 IR ctors to 1 (scope sum mirrors `Lang_cmake`
  exactly). `get_property` lifted from TARGET-only `{ target; set_form
  : bool }` to unified `{ scope; mode : get_property_mode }` covering
  all 8 cmake scopes. `cache_entry = Cache_entry` placeholder lifted to
  `string` (was silently dropping entry names on emit). Pos3 entity
  prototype: parser-local `cmake_entity` (`Target`/`Source`/`Cache`/
  `Test`/`Install`/`Directory`/`Global`/`Variable`) + `p_cmake_entity`
  reading group used by set_property + get_property. `:=` low-priority
  command-call sugar: `var := get_property Target foo ~property=NAME`
  desugars to `~out=var`.
- **LSP (yelu-lsp + VS Code extension).** ✅ Shipped 2026-06-10..20.
  `linol-lwt`-based stdio server, parse diagnostics with token spans
  (M1.5b), `textDocument/formatting` via `Yc_driver.format`,
  publishDiagnostics for every wellform finding (Error / Warning /
  Information severity) with whole-word source-text span heuristic.
  `fmt` is fail-safe (refuses to overwrite on fatal wellform — typos
  stay visible). VS Code client at
  [`editors/vscode/yc/`](../editors/vscode/yc/); cross-pack contract in
  [`driver.md`](framework/driver.md) §6.5. Design in
  [`surface_lsp_framework.md`](yelu_cmake/surface/surface_lsp_framework.md).
- **TextMate grammar + co-truth lock.** ✅ Shipped 2026-06-10. Generated
  from `Yc_manifest`; the chain `Yelu_lexer.{constr_names,command_names}`
  → `Yc_manifest` → `Yc_tmgrammar` → committed `yc.tmLanguage.json` is
  fully locked. Vocabulary drift fails `dune test` until `dune promote`.
- **Syntax audit closure + honest emit.** ✅ 2026-07-16. A two-pass audit
  (internal 3-agent + external re-audit) of the 2026-06 syntax arc closed all
  four findings: **honest emit** (`a57bcf4` — an unresolved bare `EVar`
  renders as a *literal* in all five renderers, matching cmake's model, which
  removed the target-name deref *and* the slot-dependent coercion behind it);
  `Unknown_kwarg` (an unknown `~label=` on a known command is fatal, not a
  silent drop); labeled-only find / add_test / property; and a world-aware
  `Function_def_typo`. The fmt matrix gained the **tripled oracle** (`6aae29a`
  — CMakeCache + file-api codemodel-v2 + ctest `--show-only=json-v1`), which
  immediately caught a contaminated `vendor/fmt/CMakeLists.txt` and a
  never-ported test block. Arc in [`worklog_2026_06.md`](worklog/worklog_2026_06.md).
- **Tier (b) — legacy parser retired.** ✅ 2026-07-16. `Yc_driver.parse_yc =
  parse_cst ∘ lower_cst`; the token-level grammar in `yelu_parse.ml` is
  deleted (−1067 lines), leaving it as the per-command `_inner`
  argument-interpretation library (name → positionals → kwargs → `expr
  option`) that `Yc_cst_lower` dispatches to. The migration discipline (build
  beside, lock with an oracle, retire) is written up in
  [`surface_lsp_framework.md`](yelu_cmake/surface/surface_lsp_framework.md) §8.
- **yc/ycn boundary rule adopted.** ✅ 2026-07-16.
  [`yc_ycn_boundary.md`](yelu_cmake_normal/typing/yc_ycn_boundary.md): yc = anything that
  *erases* to cmake with no semantic gap; ycn = anything needing a value/type
  model. Settles Y17 (typing → ycn) and Y18 (constructor = yc, value class =
  ycn).
- **Command-coverage + dispatch locks; command reference generated.** ✅
  2026-07-20. A coverage scan found 15 of 138 commands with no test and 5
  silently broken (9 `cmake_path` ops dropping `~out=`; `add_exe_alias` /
  `add_lib_imported` / `precompile_headers` with no `.yc` surface at all,
  emitting their yc name as bogus cmake; `add_lib_alias` self-aliasing). All
  fixed and now guarded: the coverage lock (every command has a golden), the
  dispatch lock (every command is owned by a family `_inner`), and a
  **generated** [`yc_command_reference.md`](yelu_cmake/surface/yc_command_reference.md)
  freshness-locked against `yelu command-reference`.
- **Bar #3 — scale beyond fmt (z3 / llvm / torch).** ⏳ Not started; fmt is
  the first completed whole-project proof, while this is the manifesto-level
  generalization test. Reframed
  2026-06-04 as a gradual hybrid adoption strategy
  (cmake-as-assembly, per-helper migration, raw_cmake escape) —
  see [`hybrid_strategy.md`](yelu_cmake/hybrid_strategy.md).
  Next probe will pick the second project per
  [`candidates.md`](../probes/candidates.md).

Full chronological history in [`worklog_2026_05.md`](worklog/worklog_2026_05.md)
and [`worklog_2026_04.md`](worklog/worklog_2026_04.md). Current TODOs
in [`status.md`](status.md).

## Open work

All open / unfinished work — the ycn agenda, Y17 typing, the behavior-level
oracle, IR/harness cleanups, deferred loaders, surface polish, and the numbered
**Y2–Y18** backlog — lives in the single tracker: **[`status.md`](status.md)**.
This overview records what's *shipped* (§ Project-level milestones) and the
architecture; open items are **not** duplicated here.

**Known architectural limitations** (all tracked in `status.md`): no CI; no
`effect` or systematic `lower` checking pass; lossy `Lang_cmake_pp` arms
(surfaced by Bar #3-lite); comments inside argument lists are dropped;
single-file LSP; the Pos3 `cmake_entity` is parser-local (→ Y18 value class,
ycn). Closed since the previous audit: concrete-syntax parser, yelu_legacy E1
retirement, surface canonical form, LSP/formatter, the cmake-stdlib name cache,
`Function_def_typo`-in-compile, open-world corpus false positives.

## Documentation

The documentation landing page and complete categorized index live in
[`doc/README.md`](README.md). Its placement rule is the short version of the
architecture above: CMake ground truth → `cmake/`; reusable machinery →
`framework/`; faithfully erasable CMake constructs → `yelu_cmake/`; constructs
that need a value/type model → `yelu_cmake_normal/`.

Document ownership is deliberately narrow:

- unfinished work → [`status.md`](status.md)
- shipped architecture, evidence, and milestones → this overview
- navigation and document authority → [`README.md`](README.md)
- chronological completion record → [`worklog/`](worklog/)
- resolved or superseded notes → [`archive/`](archive/)
