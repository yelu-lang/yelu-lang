# Yelu — Project Overview

> Last full pass: 2026-06-21. Surface track (no-ALL_CAPS `~`-half + labeled-only
> Step 2), property-family unification, Pos3 entity prototype, `:=` command-call
> sugar, and the LSP (formatting + wellform diagnostics + parse-error spans) all
> landed 2026-06-13..20 and are reflected below.

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
contract in [`yelu_cmake/driver.md`](yelu_cmake/driver.md) §6.5: fatal
findings exit the per-file compile, refuse format, become Error
diagnostics in the LSP. Warnings appear in stderr / Problems panel but
don't block.

The earlier per-fragment `Stage_typecheck` pass was retired alongside
the legacy production AST (commits up to E1, 2026-05-14). Y17 — a fresh
typing pass over the post-retirement `yelu_cmake` / `yelu_cmake_normal`
IR — is the replacement; tracked in
[`yelu_cmake/status.md`](yelu_cmake/status.md) "Open work".

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
| Unit tests (`dune test`)           | ~991     | Pretty-printer, compile, parse, eval, lift/lower, steps, surface (lexer / parser / CST / emit-bridge oracle / co-truth locks / grammar freshness), per-theory check/compile suites. |
| **Corpus compile gate** (in `dune test`) | every `.yc` under `probes/fmt` | `yelu compile-corpus probes/fmt` — parse + wellform + emit each file; fails the build on a positional cmake-keyword form, enum-shadow, parse error, or emit crash. Closes the blind spot where `compile main.yc` was byte-identical but discovered helpers (`probes/fmt/test/*/CMakeLists.yc`) had regressed. |
| `make runcmake-yelu`               | 50 / 50  | yelu-generated scripts vs cmake reference output.             |
| `make cmake-only-check`            | 12 / 12  | Structural equivalence for `Tests/CMakeOnly/`.                |
| `make cmake-check-v1`              | 24 / 24  | Tutorial v1 structural-equivalence via gersemi.               |
| `make cmake-check-v2`              | 11 / 11  | Tutorial v2 structural-equivalence via gersemi.               |
| `make file-api-test`               | 12 / 12  | codemodel-v2 JSON diff on tutorial steps.                     |
| End-to-end (`make step1`–`step12`) | 12       | Generate → configure → build → run.                           |
| Bar #3-lite parse-print round-trip | 740 / 740 (canonical) + 3004 / 3035 (full llvm-project) | tutorial 25/25 + fmt 11/11 + z3 108/108 + llvm/llvm 596/596 = canonical 740. Full llvm-project (3035 files) adds 3004 OK + 1 FORMAT + 30 STRUCT pre-existing. See [`worklog_2026_06.md`](worklog/worklog_2026_06.md). |
| fmt cache matrix smoke             | 24 / 24 cells | Predicted vs real cmake cache per (option × ON/OFF); median matched=20, mismatched=0, real-only=0, pred-only=0. See [`../probes/cache_matrix.md`](../probes/cache_matrix.md). |
| tm-grammar co-truth lock           | 1        | `dune promote` round-trip: committed `editors/vscode/yc/syntaxes/yc.tmLanguage.json` byte-matches what `yelu tmgrammar` emits from `Yc_manifest`. Surface-vocabulary drift fails the build. |

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
  writeup at [`worklog_2026_06.md`](../doc/worklog/worklog_2026_06.md).
  Extended 2026-06-03 to include fmt (11/11 OK) and the full llvm-project
  corpus (3004/3035 OK + 1 FORMAT + 30 STRUCT pre-existing).
- **Cache namespace + `-D` cmd-line input.** ✅ Shipped 2026-06-01.
  `ECmakeSetCache` and `ECmakeOption` now write into `env.cache_vars`
  (separate from `env.frames`); `-D` populates cache before eval so
  `option()` is correctly a NO-OP when the entry exists. Record in
  [`worklog/worklog_2026_06.md`](worklog/worklog_2026_06.md)
  (§ "Cache namespace + `-D` cmd-line input — shipped").
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
- **Surface syntax — no-ALL_CAPS pass (the `~`-half).** ✅ Shipped
  2026-06-04..19. Every cmake keyword arg is now a labeled argument
  (`~flag` / `~label=value` / `~label=[list]` / `~properties={record}`)
  or an explicit `yc_raw` escape. Casing lanes (enum constructors
  leading-cap), `$foo` brace-elision, single-quote canonical strings.
  Empirical cmake ground truth recorded in
  [`cmake/painpoints.md`](cmake/painpoints.md) §11. See
  [`worklog/worklog_2026_06.md`](worklog/worklog_2026_06.md) "2026-06-19".
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
  [`yelu_cmake/driver.md`](yelu_cmake/driver.md) §6.5. Design in
  [`lang/surface_lsp_framework.md`](lang/surface_lsp_framework.md).
- **TextMate grammar + co-truth lock.** ✅ Shipped 2026-06-10. Generated
  from `Yc_manifest`; the chain `Yelu_lexer.{constr_names,command_names}`
  → `Yc_manifest` → `Yc_tmgrammar` → committed `yc.tmLanguage.json` is
  fully locked. Vocabulary drift fails `dune test` until `dune promote`.
- **Bar #3 — real-world cmake hand-rewrites (z3 / llvm / torch).** ⏳ Not
  started; the manifesto-level "does this scale" test. Reframed
  2026-06-04 as a gradual hybrid adoption strategy
  (cmake-as-assembly, per-helper migration, raw_cmake escape) —
  see [`yelu_cmake/hybrid_strategy.md`](yelu_cmake/hybrid_strategy.md).
  Next probe will pick the second project per
  [`../probes/candidates.md`](probes/candidates.md).

Full chronological history in [`worklog/worklog_2026_05.md`](worklog/worklog_2026_05.md)
and [`worklog/worklog_2026_04.md`](worklog/worklog_2026_04.md). Current TODOs
in [`yelu_cmake/status.md`](yelu_cmake/status.md).

## Gaps

| Gap                              | Category     | Notes                                                |
| -------------------------------- | ------------ | ---------------------------------------------------- |
| No CI                            | Infra        | Yelu can break silently.                             |
| ~~No concrete-syntax parser~~    | Language     | ✅ `Yelu_parse` (Angstrom + pure OCaml, 2026-05-04). |
| ~~Retirement of yelu_legacy~~    | Refactor     | ✅ Through E1 (2026-05-14); E2 (delete) pending Y17. |
| ~~No surface-syntax canonical form~~ | Language | ✅ no-ALL_CAPS + Step 2 labeled-only complete (2026-06-19). |
| ~~No LSP / formatter~~           | Tooling      | ✅ `yelu-lsp` + VS Code extension (2026-06-10..20).  |
| No fresh typing pass             | Checker      | Y17 — design ground prepared by theory-fragment split. |
| Lossy `Lang_cmake_pp` arms       | Compiler     | Surfaced by Bar #3-lite; tracked in `yelu_cmake/status.md`. |
| No effect pass                   | Checker      | No execution-mode validation.                        |
| No systematic lower pass         | Compiler     | Panics on malformed input.                           |
| Comments inside argument lists   | IR shape     | Currently dropped; whether IR should carry them is open. |
| cmake-stdlib not in `command_names` | Wellform UX | `cmake_parse_arguments`, `check_language`, `cuda_add_executable`, … fire as `Unknown_command`. 935-callable index already in `tool/cmake_text/`; needs loading into wellform. Candidate next step (C). |
| Wellform findings carry no spans | LSP UX     | LSP scans source text for first whole-word match. Heuristic but practical; native spans → exact squiggle highlight. |
| `Function_def_typo` not in compile | Coverage  | CST-level check; `Yc_driver.format` + LSP run it but `compile` uses legacy direct parser (no CST). |
| Open-world false positives in corpus | Coverage | `probes/fmt/test/cuda-test/CMakeLists.yc` (`cuda_add_executable`) + `compile-error-test` (`cmake_parse_arguments`) need `yc_raw` or stdlib-index integration. |
| Single-file LSP                  | Tooling      | LSP sees one file at a time; no cross-file `function`/`macro` collection across `include`/`add_subdirectory`. |
| First-class cmake entity is parser-local | Language | Pos3 prototype (`cmake_entity` in `yelu_parse.ml`) — promoting to a real IR value class is Y18, design in `lang/object_value_design.md`. |

## Implementation Queue

### Code-ready next steps

| ID  | Title                                | Description                                                   |
| --- | ------------------------------------ | ------------------------------------------------------------- |
| C   | cmake-stdlib name index → wellform   | Load the 935-callable `tool/cmake_text/` index into a separate `cmake_stdlib_names` set; silences legit-but-noisy `Unknown_command` warnings (`cmake_parse_arguments`, `check_language`, …) without forcing `yc_raw`. Lets closed-world escalation cover more files. |
| —   | 2nd probe project                    | Pick from [`../probes/candidates.md`](../probes/candidates.md) (z3 / llvm subset / torch); next probe per [`yelu_cmake/hybrid_strategy.md`](yelu_cmake/hybrid_strategy.md). |
| —   | `Function_def_typo` in compile path  | Today only fmt + LSP run `Yc_wellform.check_cst`; `compile` uses the legacy direct parser. Either route compile through CST or parallel-parse for this check. |
| —   | Wellform finding token spans         | Findings carry only names; LSP scans source for whole-word match. Native spans → exact squiggle highlight + multi-occurrence diagnostics. |
| —   | IR-printer cleanup (Bar #3-lite follow-up) | Tier 1/2/3 plan in [`yelu_cmake/status.md`](yelu_cmake/status.md). |
| —   | Yelu CI                              | Build + test on push.                                         |
| Y2  | Option combination enumeration       | 2^n boolean combos for step4+, File API diff.                 |
| Y5  | File API cache-v2 diff               | Extend oracle beyond codemodel-v2.                            |
| Y12 | Cmake-layer test mirroring           | Sync cmake PP tests with yelu coverage.                       |
| E2  | Delete `yelu_legacy/`                | Mechanical follow-up to E1; gated on Y17 not needing it.      |

### Surface polish (parked, no hurry)

Open items in [`lang/yc_syntax_critique.md`](lang/yc_syntax_critique.md) § Open / remaining:

- **Version literal** — `cmake_minimum_required 3.8...3.25` as a first-class unquoted literal (lexer token for `N(.N)*(...N(.N)*)?`).
- **Per-mode `message_*` aliases** — `message_fatal` / `message_warning` / `message_status` desugar to `message ~mode=…`.
- **`Apply_shadows_primitive` check holes** — `add_custom_command` missing from `command_names`; first-class error message rather than buried generic warning.
- **Orphaned `Yelu_emit_main`** — legacy `.ml`-emit helper unused after retirement; delete candidate.
- **Latent `set_target_properties` target-deref bug**.

### Design (before coding)

| ID  | Title                          | Description                                                          |
| --- | ------------------------------ | -------------------------------------------------------------------- |
| Y6  | Semantics hardest to preserve  | Genex, policy stack, find_package search.                            |
| Y7  | Cache-sensitivity annotations  | `Cache_breaking | Cache_safe | Cache_partial`.                       |
| Y11 | Policy-aware compiler          | Auto-emit policy preamble per construct.                             |
| Y13 | Persistent value primitive     | `@cached` with content-addressed store.                              |
| Y14 | Reserved keyword validation    | ⚠️ partial — `Enum_shadow` shipped fatal at wellform; `Unknown_command` + `Function_def_typo` shipped 2026-06-20. Broader cmake-keyword clashes still open. |
| Y15 | Binding feature library        | Design space (lexical/global, mutable/immutable, expr/stmt).         |
| Y16 | Real-world cmake hand-rewrite  | z3 / llvm / torch builds in yelu, prove structural equivalence. Reframed as hybrid adoption — see [`yelu_cmake/hybrid_strategy.md`](yelu_cmake/hybrid_strategy.md). |
| Y17 | Types on yelu_cmake            | Fresh typing pass over post-retirement IR (replaces retired per-fragment `Stage_typecheck`). |
| Y18 | First-class object value       | Promote the Pos3 parser-local `cmake_entity` to a real value class. Design questions in [`lang/object_value_design.md`](lang/object_value_design.md). Operations per kind, value flow, eval semantics, wellform integration, yc vs ycn placement, UFCS `x.f y ≡ f x y` for object-method syntax. |

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
| `lang/concrete_syntax_parser.md`           | Implemented two-pass parser (Angstrom + pure OCaml).               |
| `lang/surface_status.md`                   | Living tracker for the surface track (highlighter → formatter → LSP). Per-milestone status, deferred items, decisions parked. |
| `lang/surface_lsp_framework.md`            | Surface + LSP design. §3 decision map (parser library, error recovery, deployment, testing). §7.5 wellform diagnostics — full per-check table, open/closed-world rule for `Unknown_command`, surfacing channels. |
| `lang/yc_syntax_critique.md`               | yc surface critique + the design that fixed it. Both surface passes archived; remaining open polish items at the bottom. |
| `lang/casing_design.md`                    | Casing lanes — enum constructors leading-cap, dotted globals, locals, Y14 reject. Shipped 2026-06-12..19. |
| `lang/var_centric_design.md`               | Postponed direction: value-default reads (`foo` = value, name explicit). Belongs in ycn not yc. |
| `lang/object_value_design.md`              | Y18 design questions for promoting the Pos3 parser-local `cmake_entity` to a real value class. |
| `yelu_cmake/design.md`                     | Durable design notes for the yelu_cmake harness.                   |
| `yelu_cmake/driver.md`                     | Per-language driver modules + cross-lang pipelines + tool interface. §6.5 the compile/wellform/format/LSP contract that any new pack inherits. |
| `yelu_cmake/ir_tiers.md`                   | 4-tier IR fidelity: typed → `cmake_lang` → `yc_raw` → `yc_apply`. Parser fallback strategy, string-as-enum plan. |
| `yelu_cmake/structure.md`                  | Code-anchored guide to the yelu_cmake modules.                     |
| `yelu_cmake/cmake_vs_normal.md`            | yc ↔ ycn ecosystem comparison: per-theory fragment coverage.       |
| `yelu_cmake/io_architecture.md`            | I/O library/runner split + callback-via-env pattern (include_loader, subdir_loader). |
| `yelu_cmake/hybrid_strategy.md`            | Y16 reframed: cmake-as-assembly; gradual hybrid adoption (.yc + .cmake side-by-side, or whole-file w/ raw_cmake escape). |
| `yelu_cmake/status.md`                     | Living tracker for current open work (IR cleanup, Y17, E2, etc.).  |
| `../probes/README.md`                         | Probe cluster intro: real-world cmake projects as predictor testbeds. |
| `../probes/candidates.md`                     | Shortlist of next projects to probe.                               |
| `doc/worklog/worklog_2026_06.md` | Parse-print oracle close (2026-05-31) + fmT migration + driver architecture. |
| `probes/cache_matrix.md`       | fmt matrix smoke coverage pipeline walkthrough.                    |
| `../probes/fmt/README.md`            | fmt probe status — 24/24 cells perfect; project spec; adaptation footprint; hybrid pilot result. |
| `../probes/fmt/migration_status.md`  | fmt full-project migration status — all 7 phases closed; configure-time oracle + raw_cmake + unverified Windows/CUDA limits documented. |
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
