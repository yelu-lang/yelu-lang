# Yelu Worklog — May 2026

Implementation history for the `yelu_tiny` composition harness.
For current TODO see `yelu_tiny/status.md`; for project-wide
context see `yelu_project_overview.md`.

---

## yelu_tiny composition harness — overview

`yelu_tiny` is a parallel implementation track that re-shapes the
production `yelu_cmake` AST into a *two-axle* layout:

```
Yelu1 = tiny core + cmake-shaped surfaces  (production-compatible)
Yelu2 = tiny core + idealized theories    (refinement target)
```

Three milestones (bars):

- **Bar #1** — tutorial v1 step1–step12 bridge through tiny and
  configure through real cmake.
- **Bar #2** — every production theory (14) has at least a first
  slice in tiny.
- **Bar #3** — real-world cmake rewrites (e.g. z3, llvm, torch)
  flow through tiny end-to-end.

May 2026 reached **Bar #2** (all 14 theories) and **Bar #1 for the
v1 tutorial** (all 12 root steps).

---

## Prototype and theory expansion (2026-05-01 → 2026-05-03)

Initial harness commit `5f62e21` introduced the tiny core plus
fragments for the core theories. Subsequent commits filled in the
remaining theories so each had a first slice:

| Commit | Slice | What was added |
| --- | --- | --- |
| `5f62e21` | Prototype | `yelu_tiny.ml`, env, eval, first fragments |
| `039fd20` | Custom targets | `ECmakeAddCustomTarget` / `ECmakeAddCustomCommand`, build-check tests |
| `d8d15c8` | Target + install | `target_compile_options`, install constructor surfaces |
| `d200786` | File theory | First slice of file I/O surface |
| `63334b5` | add_library + file | Library target form, more file ops |
| `970d4d2` | 6 more theories | `cmake_op`, `dir`, `test`, `property`, `find`, `try` first slices |

At the end of this run **Bar #2** was reached: all 14 production
theories had a tiny first slice plus a matched theory/surface pair.

---

## ELet + emit substitution (2026-05-03 → 2026-05-04)

The bridge needed a compile-time `let` to translate the `ylet "x" v`
production idiom without leaking through to runtime `set()`.

| Commit | What was added |
| --- | --- |
| `5d9304c` | `ELet { var; value; body }` in tiny core (canonical let-expression) |
| `93b52ae` | **Phase 2a:** emit walks an env of bindings; arg / target_arg consult it. ELet header is dropped from emitted cmake. |
| `42ce435` | **Phase 2b:** surface target-name positions typed `expr` (was `string`). `EVar` / `ETarget` survive into emit so substitution actually fires through target-name positions, not just argument positions. |

After 2b, `ylet "tut" (ytval "Tutorial")` followed by
`add_executable(yvar "tut")` emits `add_executable(Tutorial …)`, not
`add_executable(tut …)` or a stray `set(tut "Tutorial")`.

---

## Module split (2026-05-04)

The single `yelu_tiny_eval` module grew unwieldy. Split into five:

| Commit | What was added |
| --- | --- |
| `6bb0659` | Split `yelu_tiny_eval` into `yelu_tiny_yelu1` / `yelu_tiny_yelu2` / `yelu_tiny_translate` |
| `c52164c` | Drop the eval shim; group env fields by cmake phase (configure-time / build-time / install-time) |
| `eb3826b` | Reorganize tiny tests into `test_yelu_tiny_{bridge,emit,lift_lower,steps,function}` |

Net result: tiny core has one module per concern, env layout matches
cmake's lifecycle phases, tests group by what they prove (bridge,
emit, lift/lower roundtrip, step pipeline, function semantics).

---

## Function theory F2 (2026-05-05 → 2026-05-09)

`cmake function()` is the first construct whose semantics (dynamic
scope with shallow binding) doesn't fall out of straightforward
recursive lowering — it needs an activation record.

| Commit | What was added |
| --- | --- |
| `02ad6c9` | PLAN: rewrite Next Steps with breadth-first tier list (A–G) for steps 6–12; F2 design decisions (call-by-value, dynamic scope, shallow binding, deferred macro/ARGV) |
| `da16f88` | F2: `EDynFunction` / `EApply` (theory) and `ECmakeFunction` / `ECmakeApply` (surface); env.functions; save/bind/eval/restore activation record; 13 dedicated theory tests in `test_yelu_tiny_function.ml` |
| `8cb3731` | Rename theory `EFunction` → `EDynFunction`, reserving the unmarked name for a future lexical-scope sibling. Adopted canonical PL terms (Bobrow & Wegbreit 1973, EOPL) in code comments and docs. |

The two scope wrinkles cmake adds — *reads see the caller's scope*,
*writes are local to the activation frame* — fall out of the
save-and-restore design directly. Side effects on non-variable env
state (targets, tests, install_rules, messages) persist across the
call, matching cmake.

---

## Bar #1 tier list — Tier A through F (2026-05-09 → 2026-05-10)

The PLAN's tier list cleared steps 6–12 breadth-first. Each tier is
the smallest representative slice that gets the step to bridge and
(where applicable) configure through real cmake.

| Tier | Commit | Steps cleared | What was new |
| --- | --- | --- | --- |
| **A** | `86c640d` | step6, step6_ctest | `include()` first slice: theory `EInclude { file; optional }`, env.includes, emit `include("FILE")` / `include("FILE" OPTIONAL)`. |
| **B** | `abb501f` | step7, step7_math | Bridge fix: drop `command_name` short-circuit (latent incompleteness from phase 2b) so `EVar` survives in `yc_function`/`yc_apply` name position. New `let_value` helper maps `ycstr name` to `EString` in let-value position (avoids self-cycle from `ylet "x" (ycstr "x")` and unintended deref from `ylet "x" (ycstr "literal")`). Surface `ECmakeApply` lenient on unknown function (cmake routinely dispatches through `include()`d module functions tiny doesn't simulate); theory `EApply` stays strict. Split `unknown_function_fails` test into lenient surface + strict theory cases. |
| **C** | `1fbf895` | step8_table, step8_math | No new fragment work. step8_table uses `add_custom_command(OUTPUT ...)` (already bridged via `Ytgt_add_custom_command`). TARGET-form sibling remains deferred — no v1 step uses it. |
| **D** | `dd8f0bf` | step9, step10 | No new fragment work. `cpack_basic` and `shared_libs_output_dirs` compose from existing pieces. |
| **E** | `48369f0` | step11_config | `yc_at_var key` slice: theory `EAtVar of string`, surface `ECmakeAtVar`, emit renders `@key@` as a bare line. Eval is a no-op — the literal is substituted later by `configure_package_config_file` over a `.cmake.in` template. |
| **F** | `c7fabd7` | step11, step12 | Package-config family: `EInstallExport` / `EExportExport` / `EConfigurePackageConfigFile` / `EWriteBasicPackageVersionFile` (theory + surface), four matching env install_rule variants, exhaustive install bridge (catch-all removed), emit follows production cmake pretty-printer (FILE / NAMESPACE / NO_SET_AND_CHECK_MACRO / NO_CHECK_REQUIRED_COMPONENTS_MACRO / VERSION / COMPATIBILITY / ARCH_INDEPENDENT). |

After Tier F: **v1 step1–step12 (root) bridge**; step1, 2, 3, 4, 5,
6, 7, 8_table, 10, 12 configure through real cmake. step6_ctest,
step7_math, step8_math, step9, step11, step11_config bridge (separate
cmake tests subsumed by cumulative step10 / step12 fixtures).

### Tier G — deferred

Remaining cleanup: `ECmakeOption` eval through `eval` (currently
ad-hoc match); `ECmakeSetTestsProperties` eval through a new env
namespace; `set_property(TARGET ...)` as the older sibling of
`set_target_properties`. None gate further step coverage.

---

## Patterns worth keeping

- **Bridge fixes were latent incompleteness, not bugs.** Two of three
  Tier B fixes (`command_name` short-circuit; `Yexpr_name { Ns_var }`
  in let-value position) were correct under narrower assumptions
  that earlier steps happened not to exercise. The third (lenient
  `ECmakeApply` on unknown function) was a realism gap — cmake's
  permissive lookup wasn't modeled. See `yelu_tiny/design.md`
  Tier B for the full rationale.

- **Step coverage rarely needed new fragments.** Tiers C and D
  required *only* test additions; the bridge already covered the
  constructs. Tier E added one tiny constructor; Tier F added four.
  This suggests the production theory carving (14 theories) was
  reasonably complete before tiny started; tiny is mostly a
  re-shaping rather than a re-listing.

- **Test infrastructure size.** As of 2026-05-10:
  - `src/langs/yelu_tiny/` — 4,001 lines
  - `test/test-yelu/test_yelu_tiny_*` — 3,442 lines
  - 655 unit tests + 40 cmake-backed configure tests pass.

---

## Retirement (May 11 — May 14)

After Bar #2, the second half of May closed out retirement of
`src/langs/yelu_legacy/` from the production path. Items D, E-lite,
E-utils, G, F all landed by 2026-05-11; E1 closed 2026-05-14.

**What landed**

- **Item D** — `yelu_tiny` renamed to `yelu` everywhere.
- **Item E-lite** — legacy parser + lexer relocated to
  `src/langs/yelu_legacy/`.
- **Item E-utils** — 22 step binaries (`src/bin/yelu/v1`, `v2`,
  top-level) emit Yelu1 IR directly via `Yelu_cmake_utils`;
  `print_cmake` now uses `emit_ast` (no bridge call) for step
  output.
- **Item G** — language-name honesty. The two surfaces are
  `yelu_cmake` (CMake-faithful) and `yelu_cmake_normal`
  (normalized), with the bare prefix belonging to the workhorse.
  Bridge moved to `yelu_legacy/`. Enum-string converters
  extracted to `Lang_cmake_strings` in the cmake layer.
  Fragments renamed (`yelu_theory_*` → `yelu_cmake_*` /
  `yelu_cmake_normal_*`). Lexer relocated.
- **Item F** — parser dispatchers route through `Yelu_cmake_utils`
  (one source of truth for command-shape decisions; -86 LOC in
  `yelu_parse.ml`).
- **Item E1 (2026-05-14)** — legacy made deadcode. Four commits:
  - `c85fb3d` — byte oracle (194 programs) and pair-wise parser
    oracle (125 cases) rewritten with inline expected strings
    frozen from the legacy reference; `test_yelu_bridge.ml`
    deleted.
  - `d0def93` — 22 step binaries + step-shaped tests off legacy
    `Step_common`; legacy variant deleted; `ylet` fixed to
    demote `EVar n → EString n` at bind time (mirrors the
    bridge's `let_value`; without it `emit_debug.arg`
    infinite-looped on `ylet "x" (ycstr "x")`).
  - `a99d9f7` — `test/test-yelu` pool migrated;
    `yelu_test_helpers.ml` shed bridge wrappers;
    `test_yelu_cmake_parse.ml` structural helpers rewritten to
    pattern-match `Yelu_cmake.expr` IR shapes;
    `test_yelu_check.ml` deleted (it tested
    legacy-only `Cmake_check` + `Lang_yelu_wellform`; Y17 is
    the planned replacement); 15 legacy-only parser test cases
    dropped.
  - `5b11ae7` — 26 `test/test-runcmake/*` files migrated off
    `Lang_yelu_compile` to the IR + `emit_ast` path;
    `Yelu_cmake_utils` gap-fills (~150 lines: yc_string family
    extensions, list_transform, ygreater/yless,
    yc_link_libraries, math output_format accept-and-discard,
    separate_arguments `?input` shape fix);
    `ECmakeAddCustomCommand` added to `emit_ast`; `add_exe` /
    `add_lib` `~exclude_from_all` silently drops;
    `test_runcmake_yelu.ml` shed its dual-path
    `check_tiny_matches_ref` machinery; `src/langs/dune`
    excludes all 24 yelu_legacy modules from the `yelu_langs`
    library.

**E1 audit follow-up (2026-05-14)** — `fd9da5e` refreshed
`status.md` + `retirement_plan.md` and added an audit prompt
template; `659d6d0` actioned the audit's "fix before E2" items:
wrong-shape stubs (`ystrless`/`ystrgreater` family, JSON ops,
`yc_add_custom_command_target`) converted to explicit `failwith`;
9 JSON tests + 4 string-comparison tests + 2 custom-command-target
fixtures dropped; `test_yelu_utils_stubs.ml` added with 10
pinning tests (3 accept-and-discard + 7 failwith) so future IR
fixes produce visible test diffs.

**Final state**
- 1010 unit tests + 50 runcmake-yelu pairs + 12/12
  cmake-only-check + 12 step tests green.
- `yelu_legacy/` stays on disk but no `src/` or `test/` file
  imports any of its 24 modules; `src/langs/dune` enforces
  this via `(modules :standard \ …)`.
- `make cmake-commands` was already broken pre-E1
  (`Failure("expected target name")` on `a99d9f7`); the 12
  post-E1 failures it shows are not regressions (verified by
  `git stash` rollback).

**Known IR shape gaps carried forward** (tracked in
`doc/yelu_cmake/status.md`)
- String-order conds (`STRLESS` / `STRGREATER` / etc.) — IR has
  only `STREQUAL` via `ECmakeStringEqual`.
- `add_executable` / `add_library` with `EXCLUDE_FROM_ALL` — IR
  ctors don't carry the flag; helper drops silently.
- `target_link_libraries` multi-target — IR surface still takes
  a single target.
- `add_custom_command(TARGET ...)` — IR has only OUTPUT form.
- `math ~output_format` — IR doesn't carry the format; helper
  emits decimal regardless.
- JSON ops — IR's `ECmakeStringJson` is opaque (op_name + path
  dropped).

---

## Bar #3-lite — syntactic cmake round-trip (May 15 — May 20)

The Bar #3-lite milestone built a tree-sitter-based round-trip
oracle for real-world cmake source, exercising the production
`Lang_cmake.exp` IR + `Lang_cmake_pp` printer end to end. Audit-
ready state lives at `doc/yelu_cmake/bar3_lite.md`; this section
is the chronological record.

### Stages

| stage | commit | what landed |
| --- | --- | --- |
| Stage 1 | `730bb56` | Untyped tree-sitter round-trip; CST-JSON via Python wrapper; verbatim reprint. |
| `.cmake.in` fallback | `e86d64c` | ERROR-root templates passed through as raw text. |
| Stage 2 | `56f01c2` | Typed mapping into `Lang_cmake.exp` via per-command parsers + production printer. |
| IR fix #1 | `13d813c` | `Include.no_policy_scope`: `scope option` → `bool`. |
| Comments + casing | `c52b782` | Comment preservation; lowercase guard in dispatch. |
| Apply fallthrough | `46eea0c` | Generic-bucket routing through `Lang_cmake.Apply` + first batch of structural bug fixes. |
| IR fixes #2-4 | `6a6295a` | `Configure_file @ONLY/ESCAPE_QUOTES` cross-swap; `Include.result_var` keyword emission; `pp_arg.Bracket` newline stripping. |
| IR fix #5 | `91cb43e` | `Lang_cmake.arg.Bracket` widened to `int * string`. |
| FORMAT closed | `155e8e3` | All 729 files OK across tutorial + z3 + llvm. |
| Stage 2-b | `7c1d8a9` | 8 mechanical typed parsers (`unset`, `add_dependencies`, `find_package`, `get_filename_component`, `set_target_properties`, `add_custom_target`, `list`, `string`). |
| Stage 2-c | `3217f9b` | 7 more typed parsers (`return`, `include_directories`, `find_program`, `find_path`, `install`, `add_custom_command`, `file` subcommands). |
| Terminology | `5ef9eb9` | `typed` → `modeled`; dropped the misleading ratio. |
| Audit pass | `b9a4c38` | Deleted dead `print.ml`; refreshed README + headers. |

### Production IR bugs surfaced

Five bugs in the production IR + printer that the synthetic
tutorial corpus did not exercise — caught only by running the
round-trip on z3 and especially llvm:

1. `Include.no_policy_scope` typed as `scope option` (irrelevant
   enum); cmake's `NO_POLICY_SCOPE` is a boolean flag. (`13d813c`)
2. `Configure_file` flags `@ONLY` and `ESCAPE_QUOTES` wired to
   wrong fields in the printer (cross-swap). (`6a6295a`)
3. `Include.result_var` printed without the `RESULT_VARIABLE`
   keyword. (`6a6295a`)
4. `pp_arg.Bracket` added surrounding newlines around content.
   (`6a6295a`)
5. `Lang_cmake.arg.Bracket of string` lost the bracket-quote level
   (`[==[…]==]` vs `[=[…]=]`). Widened to `Bracket of int * string`.
   (`91cb43e`)

### Codex audit 2026-05-19 (audit-ready report review)

External review of the report doc raised four findings, all
addressed in commit `f931086`:

1. STRUCT extractor in `test_corpus.sh` only collected `argument`
   children inside `argument_list`. Block heads/tails (e.g.
   `endforeach(x)`) can expose `argument` directly on the
   command node. Could silently mask STRUCT failures. Fixed.
2. No gersemi pre-flight check — a missing/broken formatter
   would make both `ref` and `got` empty and FORMAT would pass
   spuriously. Hard `--version` probe + executable check added.
3. `untyped_emit` constructed `name(args)` via string
   concatenation, not via real `Lang_cmake.Apply`. Rerouted
   through the real ctor + production printer.
4. `other` bucket counter incremented once per `Block` wrapper
   plus raw/unknown — comment misdescribed it as "block
   heads/tails". Corrected.

### Codex audit 2026-05-20 (audit-kit review)

Second-round external review surfaced parser-side accept-set
holes that the kit's own discipline said shouldn't exist, plus
process gaps in the kit. All resolved in commit `db83c7e`:

1. **Parser bug**: `cmake_minimum_required` accepted `<min>...<max>`
   but printer drops `max`. Parser now detects `...` and bails.
2. **Parser bug**: `project` silently dropped DESCRIPTION /
   HOMEPAGE_URL; LANGUAGES emitted reversed due to a
   double-reverse in `split_keywords`. Bail on DESC/HU; LANG
   ordering fixed.
3. **Parser bug (typed-IR misclassification)**: `add_executable`
   put `WIN32`/`MACOSX_BUNDLE`/`EXCLUDE_FROM_ALL` into the
   `sources` field — STRUCT-faithful but the typed IR was wrong.
   Parser now bails on any reserved option keyword. **Canonical
   example of "STRUCT pass ≠ typed correctness"** — motivated
   the dual-axis review framing in the kit.
4. Stage table count inconsistency; reproducers missing the venv
   PATH; "byte-faithful Apply" overclaim; destructive `git
   checkout main -- file` in pre-commit recipe;
   `target_link_libraries` mixed-visibility groups contract row
   was wrong (they round-trip correctly). All corrected.

Corpus impact: tutorial 25/25 unchanged; z3 108/108 OK,
modeled 1057→1056, generic 706→707; llvm 596/596 OK,
modeled 3573→3572, generic 2609→2610. Both corpora still
STRUCT=0 / FORMAT=0. The −1 modeled drops are the dual-axis
correction landing.

### Doc consolidation

Bar #3-lite produced four overlapping docs during the build:
`bar3_feasibility.md`, `bar3_lite_report.md`,
`bar3_lite_audit_kit.md`, `bar3_lite_audit_review.md`. Collapsed
in two passes to a single durable doc `bar3_lite.md` (commit
`d63d7dc` + this commit), with audit history archived to this
worklog section.

### Final state

| corpus | files | OK | FORMAT | STRUCT | PARSE | modeled | generic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| tutorial step outputs | 25 | 25 | 0 | 0 | 0 | 165 | 25 |
| z3 | 108 | 108 | 0 | 0 | 0 | 1,056 | 707 |
| llvm/llvm | 596 | 596 | 0 | 0 | 0 | 3,572 | 2,610 |

30 cmake builtins modeled in `tool/cmake_roundtrip/print2.ml`.
Audit-ready writeup at `doc/yelu_cmake/bar3_lite.md`.

### Retirement final state (from the archived retirement_plan.md)

Retirement is complete through E1 (2026-05-14). The doc is now
folded into this worklog section and into `status.md`:

- `src/langs/yelu/` is the production language. No legacy
  imports anywhere in `src/` or `test/`.
- `src/langs/dune` excludes 24 `yelu_legacy/` modules from the
  `yelu_langs` library via `(modules :standard \ …)`. The
  modules stay on disk for reference.
- Production text generation routes through
  `Yelu_cmake_utils → Yelu_cmake → Yelu_cmake_emit →
  Lang_cmake_pp`. Pair-wise oracle and byte oracle are retired;
  byte-equality signal lives on as inline expected strings
  (frozen during E1) in `test_yelu_compile.ml` and
  `test_yelu_cmake_parse.ml`.

What remains, tracked in `status.md` "Open work":

- **E2 — delete `yelu_legacy/`.** Mechanical: `git rm -r
  src/langs/yelu_legacy/`, revert `src/langs/dune` to plain
  `(include_subdirs unqualified)`, drop the negative module
  list. Gated on E1 soak time and Y17 not needing legacy as a
  reference.
- **Y17 — types on yelu_cmake.** Post-retirement typing pass.

---

## Bar #3-lite milestone close (2026-05-31)

Bar #3-lite static round-trip declared complete and archived:

- Two-tier Class A name accounting shipped — corpus-local index
  + cmake-stdlib `Modules/` index (probed via `cmake -P` from
  `${CMAKE_ROOT}`, 935 callables on this host).
- Final counts: z3 108/108 OK (modeled=1,123 / stdlib=128 /
  resolved=133 / generic=379 / other=1,711). llvm 596/596 OK
  (modeled=3,863 / stdlib=164 / resolved=1,534 / generic=621 /
  other=4,029). STRUCT=0 / FORMAT=0 preserved.
- Cross-audit (independent agent, separate context) verified
  numerical match, project-first precedence in code matches
  doc, `normalize()` symmetric (cannot mask drift), § 10
  "dynamic-only" items genuinely require cmake evaluation.
  Verdict: claim holds.
- Audit-ready report preserved as-is at
  [`../yelu_cmake/bar3_lite.md`](../yelu_cmake/bar3_lite.md)
  with an archived banner.
- Forward tracking moved to
  [`../yelu_cmake/status.md`](../yelu_cmake/status.md). Lead
  next item: **Bar #3 — dynamic / behavior-level oracle**
  (configure-time File API JSON diff against real cmake;
  resolves the remaining generic by walking `include()` /
  `find_package()` chains at runtime).

## Linked artifacts

- `doc/yelu_cmake/status.md` — current open work (the slim living tracker).
- `doc/yelu_cmake/bar3_lite.md` — Bar #3-lite final report (archived 2026-05-31).
- `doc/yelu_cmake/design.md` — durable design notes.
- `doc/yelu_cmake/structure.md` — code-anchored module guide.
- `src/langs/yelu/` — the production language (post-retirement rename).
- `src/langs/yelu_legacy/` — retired reference, no longer in the
  `yelu_langs` library.
