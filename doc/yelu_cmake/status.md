# yelu_cmake — Status & Current Open Work

Living tracker. Strip and update freely; durable design is in
`design.md`, code-anchored module guide in `structure.md`,
side-by-side comparison of `yelu_cmake` and `yelu_cmake_normal`
ecosystem coverage in `cmake_vs_normal.md`, chronological history
(retirement archive + Bar #3-lite audit trail) in
`../worklog/worklog_2026_05.md` and `../worklog/worklog_2026_06.md`.

## Current state (2026-05-31)

- **Bar #3-lite static round-trip — shipped, audit-ready.** STRUCT=0 /
  FORMAT=0 across tutorial (25/25), z3 (108/108), llvm (596/596).
  Two-tier Class A name accounting (project + cmake-stdlib `Modules/`)
  shipped 2026-05-31. Full report archived at
  [`worklog_2026_06.md`](../../doc/worklog/worklog_2026_06.md); milestone arc in
  [`../worklog/worklog_2026_05.md`](../worklog/worklog_2026_05.md)
  ("Bar #3-lite" section).
- **Tier 1–4 IR-printer cleanup — shipped.** 16 commits, 358 generic
  shapes converted to modeled (z3 +67, llvm +291). Per-tier detail
  archived in `worklog_2026_05.md` ("IR-printer cleanup" section).
- **Retirement of `src/langs/yelu_legacy/` through E1 — shipped.**
  Production routes through
  `Yelu_cmake_utils → Yelu_cmake → Yelu_cmake_emit → Lang_cmake_pp`.
  `src/langs/yelu_legacy/` excluded from the `yelu_langs` library;
  no `src/` or `test/` file imports it.

Verification baseline:
- 1010 unit tests pass
- 50/50 `make runcmake-yelu`
- 12/12 `make cmake-only-check`
- 12 step tests pass
- `make cmake-commands` broken pre-E1 (unrelated cmake build issues);
  not blocking.

Parser coverage: 277 tests (126 inline-golden + 151 smoke),
~90 commands across all 14 theories. Catch-all for unknowns →
ECmakeApply, yc_raw fallback for known commands with dynamic args.
fmt probe: 11/11 .yc files compile, 24/24 matrix cells pass, 3 raw escapes
(all dynamic visibility). See `probes/fmt/README.md`.

## Architecture TODO: eval-before-emit resolve pass

The current pipeline is `parse → emit`. Raw-fallback args (e.g. `EVar "${kind}"`)
are reconstructed to cmake text at parse time via `args_to_cmake_text` and
stored as `ECmakeRaw string`. This loses type information before emit can
resolve bindings.

A resolve pass between parse and emit would evaluate statically-known
bindings (function params, local `set()` chains, option defaults) and
attempt to promote `ECmakeRawCmd` fragments to typed IR. Only configure-time
unknowns (`-D` flags, `${CMAKE_VERSION}`, file probes) would remain as
`${VAR}` deferrals.

The `yelu_cmake_eval.ml` evaluator already exists and is used by the matrix
oracle (`.ml` path). It has not yet been wired into the `.yc` → emit
pipeline.

Related: IR fidelity tiers in [`ir_tiers.md`](ir_tiers.md).
4 tiers (typed → cmake_lang → yc_raw → yc_apply)
in [`ir_tiers.md`](ir_tiers.md).

## Open work — forward

Static round-trip is at a natural stop ([`worklog_2026_06.md`](../../doc/worklog/worklog_2026_06.md) § 10).
Forward work falls into three buckets, in priority order:
(a) **the behavior-level oracle** — now the lead, since its foundational
blocker (cache + `-D` cmd-line input) shipped 2026-06-01;
(b) the language-layer cleanups that Y17 typing depends on;
(c) E2 mechanical retirement tail.

### Cache namespace + `-D` cmd-line input — *shipped 2026-06-01*

`cache_vars` namespace in `env`, `?cmd_line` input channel, cache
read-fallback, `option()` suppression, and a three-tier test suite
(unit `test_yelu_cache.ml`, dual-eval `?cmd_line` cases, real-cmake
oracle `test_yelu_cache_oracle.ml`) all landed. Full record — design,
commits, residual gaps — in
[`../worklog/worklog_2026_06.md`](../worklog/worklog_2026_06.md)
(§ "Cache namespace + `-D` cmd-line input — shipped"). Residual gaps
(`CACHE FORCE` vs `-D`, `$CACHE{VAR}` explicit read, cross-run
persistence) are in Deferred below. The plan doc (`cache_plan.md`) was
retired into the worklog.

### Behavior-level oracle — *lead* (foundation unblocked 2026-06-01)

The natural successor to Bar #3-lite. Lite proved the **syntactic** IR
shape is rich enough to carry every cmake call in real corpora.
The behavior-level oracle proves the **runtime semantics** match
real cmake. Its foundational blocker — cache + `-D` cmd-line input,
needed to ground-truth `-D`-bearing programs — shipped 2026-06-01, so
this is now the lead forward item.

> Names: this used to be called "Bar #3-full" alongside Bar #3-lite.
> Now that the syntactic milestone is shipped and archived, the
> `lite`/`full` distinction has lost its purpose — the remaining
> work is just *the* behavior-level oracle. Older references to
> "Bar #3-full" mean the same thing.

Scope:
- **Configure-time evaluation oracle.** Run real cmake against
  source `CMakeLists.txt` and yelu-emitted output; diff the
  File API (codemodel-v2 + cache-v2) JSON. Two outputs must
  match — same targets, same sources, same compile flags,
  same configured cache state.
- **Resolution of dynamic dispatch** (Class A Phase 2). Walk
  `include(...)` / `find_package(...)` chains at configure
  time to populate the project-level function table the static
  walker can't see. Currently 379 generic on z3 / 621 on llvm
  are calls into runtime-loaded helpers; this resolves them.
- **Macro vs function scope.** Today `yelu_cmake_eval` treats
  scope opaquely. Once we run real cmake side-by-side, the
  scope rules (macro = textual; function = isolated scope +
  `PARENT_SCOPE` opt-in) need explicit modeling.
- **Genex `$<...>` delay.** Currently opaque `EString`s. Lite
  round-trips them as text; Full must evaluate them at the
  right pipeline stage.

Reference points:
- The Bar #3-lite project-index TSVs are the data substrate
  Phase 2 reuses for static-name-table lookups.
- File API JSON oracle scaffolding lives in
  [`test/test-file-api/`](../../test/test-file-api/).
- `make runcmake-yelu` (50/50) is the closest existing
  behavior-level harness — yelu-emitted scripts vs cmake
  reference under `cmake -P`. The behavior-level oracle extends
  this from `-P` script mode to full configure mode.

This is the manifesto-level "does it scale" test (Y16 in
`CLAUDE.md`). Not started.

### Surface syntax + LSP (sibling track)

The *static-semantics* half to the oracle's *dynamic* half: a
higher-fidelity surface + language server for yc (then ycn), feeding off
the driver's `check` op the way the oracle feeds off `eval`. Design
exploration + decision-map in
[`../lang/surface_lsp_framework.md`](../lang/surface_lsp_framework.md)
(yc-first). **Milestone 0 — shipped 2026-06-10:** a server-less VS Code
TextMate highlighter whose `.tmLanguage.json` vocabulary is generated from
the `Yc_manifest` co-truth (test-locked to `Yc_primitives` + the lexer;
exposed via the `Yc_driver.manifest` op; emitted by `yelu tmgrammar`).
Extension under `editors/vscode/yc/`, verified on `probes/fmt/main.yc`
with the real TextMate engine. Full record in
[`../lang/surface_lsp_framework.md`](../lang/surface_lsp_framework.md)
§ Milestone 0. **Next (Milestone 1+):** parser CST/spans + error recovery,
then the LSP itself (`linol` shell over `Yc_driver`, diagnostics ← check,
semantic tokens). Not started.

### Behavior-level sequels (parked, in order)

- **Real-world cmake rewrites.** Rewrite z3 / llvm / torch
  builds in `yelu_cmake`; prove structural equivalence against
  the original CMakeLists. Once File API diff is wired, this
  becomes a tractable verification problem.
- **Optimize yelu_cmake; prove optimized ≡ original** via the
  same oracle. The yelu_cmake ↔ yelu_cmake_normal bridge
  (currently exercised only by `test_yelu_lift_lower.ml`,
  65 tests) becomes load-bearing once optimization passes
  rewrite the normal form.
- **Macro elimination.** Whether to drop `function()` /
  `macro()` from yelu_cmake in favor of pure-OCaml
  parameterization, given yelu programs are themselves OCaml.
  Decide with Bar #3 data. Memo:
  `.claude/memory/project_macro_elimination.md`.

### E2 — delete yelu_legacy/

Mechanical follow-up to E1: `git rm -r src/langs/yelu_legacy/`,
revert `src/langs/dune` to plain `(include_subdirs unqualified)`,
remove the negative-module list. Removes the brittle dune
exclusion the audit flagged. Gated on:
- E1 holding green for some soak time
- Y17 not needing legacy as a reference (decide as Y17 takes
  shape)

### Y17 — types on yelu_cmake

Post-retirement typing pass. The previous attempt (per-fragment
`Stage_typecheck`) was structurally shallow: each fragment
validated its own expression types in isolation, with `wellform`
bolted on top to handle cross-theory name binding. With the
proper theory split (`yelu_cmake` ↔ `yelu_cmake_normal`) the
type design has actual semantic ground — namespace separation
is already in `env`, mutability / set-once / identity rules
belong with each theory module, and `to_normal` / `from_normal`
give a natural place to push richer invariants.

Gating decision before Y17 starts: **how much theory-fragment
isolation to bake in first**. The current setup uses a single
extensible `Yelu_cmake.expr` (`type expr += | ECmakeX ...` per
fragment). Tighter alternatives (split `expr` per theory; share
only a small `core_expr`) are discussed in the post-retirement
cleanup list below (items 6–7). Y17 typing rules can be written
either way; the question is whether forcing the split first
makes per-theory test isolation and per-theory typing cleaner,
or whether it's reorganization for its own sake.

## Known IR shape gaps (emit side)

Documented gaps where the IR + `emit_ast` path cannot model the
full cmake surface. E1 left these as either `failwith` (helper
refuses to emit) or accept-and-discard (helper emits cmake that
ignores the unmodeled option). Pinned by
`test/test-yelu/test_yelu_utils_stubs.ml`.

The Bar #3-lite round-trip surfaced a parallel list of
printer-side lossy fields (see "Open work — IR-printer cleanup"
above; per-parser detail in `doc/worklog/worklog_2026_06.md` § 8). The two sets
overlap and would be closed by the same cleanup pass.

- **String-comparison conds beyond equality** — `STRLESS` /
  `STRGREATER` / `STRLESS_EQUAL` / `STRGREATER_EQUAL`. IR has
  only `STREQUAL` via `ECmakeStringEqual`. Helpers `failwith`.
- **`add_executable` / `add_library` with `EXCLUDE_FROM_ALL`** —
  IR ctors don't carry the flag. Accept-and-discard.
- **`target_link_libraries` multi-target** — IR surface takes a
  single target; multi-target callers must split per-target.
- **`add_custom_command(TARGET ...)`** — IR only has the
  OUTPUT-form. Helper `failwith`.
- **`math ~output_format`** — IR's `ECmakeMath` doesn't carry
  format. Accept-and-discard; tests using `Hexdecimal` get
  decimal.
- **JSON ops** — `ECmakeStringJson` is opaque (op_name + path
  dropped). Helpers `failwith`.
- **Parser sentinel defaults** — `out_var_y1` `"?"`,
  `cvar_name_of_y1` `"?"`, `expr_to_int_y1` `0` fallback,
  `string_uuid` `"ns"`/`"n"` placeholders, `cmake_minimum_required`
  `"3.20"` fallback, `project` `"Project"` fallback,
  `policy_set` `""` fallback. Vestigial from byte-equality with
  the legacy parser; tightening pairs naturally with Y17.

## Post-retirement cleanup

In order of value:

1. **Split `cmake_op`** into smaller surfaces (project/message,
   control flow, function/macro, process, policy/include).
   390-line surface + 103-line theory is the largest single
   fragment and the broadest compatibility bucket.
2. **Generated fragment coverage table** — auto-generate a
   matrix (semantics eval, lift, lower, emit, bridge, unit
   test, cmake-backed test) per fragment so coverage gaps stay
   visible as constructors are added.
3. **Move emit / convert arms closer to each fragment.**
   `yelu_cmake_convert.ml` (~1.7 k lines) and
   `yelu_cmake_emit_debug.ml` (~964 lines) are central
   registries. Per-fragment convert / emit modules reverse the
   entropy trend.
4. **Y17 — fresh typing pass on yelu_cmake** (see "Open work").
5. **Promote compat surfaces to real theories** where worth it
   (genex first, then find / try / cmake_op subsets). Pairs
   with Y17 — typing decisions inform which surfaces deserve
   the lift.
6. **Categorize `yelu_cmake_normal_*` theories: general vs
   cmake-specific.** `bool`, `int`, `string`, `list`, `store`
   are general-purpose theories any future `yelu_*` language
   (`yelu_shell`, `yelu_c`) would also want; they live next to
   the genuinely cmake-specific ones (`target`, `install`,
   `find`, `property`, `try`) only because the historical
   bundle didn't distinguish.
7. **Split the shared `expr` type between `yelu_cmake` and
   `yelu_cmake_normal`.** Today both use the same extensible
   `Yelu_cmake.expr` via `type expr += ...`; the
   `yelu_cmake` expr universe technically contains every
   `yelu_cmake_normal` ctor and vice versa. A clean separation
   gives each language its own `expr`, with shared nodes
   (`EVar`, `EString`, `EBool`, `EInt`, `ESeq`, `ELet`,
   `ESetVar`, `EUnit`) staying in a small shared core. Pairs
   with item 6 and Y17.
8. **Parser family dispatch split (`yelu_parse.ml`, ~2.1 k lines).**
   One file with 12 family parsers + dispatch + shared helpers
   (`str_of`, `collect_command_args`, `split_by_keywords`,
   `fallback_to_raw`) and mutually-recursive dispatch. Options:
   (A) per-family `.ml` + shared `yelu_parse_util.ml`; (B) keep whole
   with banner sections + TOC; (C) defer until the parser stabilizes.
   **Recommended: defer (C)** — the parser is still growing and a split
   adds friction to each new command family.
9. **CLI driver split (`yelu.ml`, ~600 lines).** Move reusable logic
   into library modules. Independent of the language layer. **Defer**
   until the driver gains a second major subcommand or ~200 more lines.
10. **Escape registry.** Track every `ECmakeRaw` / `ECmakeApply` / raw
    fallback site with reason, location, and test coverage — needed to
    scale to z3/llvm. **Start as a markdown file in `doc/yelu_cmake/`,
    not code**; code-level tracking (`reason` fields on ctors) waits for
    Y17.

(Items 8–10 migrated from the retired `refactoring_plan_2026_06_09.md`
— its P0/P1 dedup landed in `6a41f96`; see `../worklog/worklog_2026_06.md`
§ "src/langs dedup".)

## Deferred

### File loader / module system gaps

Updated 2026-06-03 after fmt matrix completion. See
[doc/yelu_cmake/io_architecture.md](io_architecture.md) §§ 5, 7
for the full picture. Pick up as cmake-corpus expansion demands them.

- **`include_guard()` + load-once cache.** Today every
  `include()` re-evaluates. Add `evaluated : Set.M(String).t` to
  env; `include_guard()` consults; subsequent loads short-circuit.
  ~20 LOC. Bites when modules accumulate state across calls.
- **`find_package(X)` real recursion.** Today: whitelist of
  assumed-found packages (`assumed_found_packages = [ "Threads" ]`
  in [yelu_cmake_find.ml](../../src/langs/yelu/fragments/yelu_cmake_find.ml))
  writes a canned `FIND_PACKAGE_MESSAGE_DETAILS_<pkg>` cache entry.
  Real implementation: third loader callback (`package_loader`) +
  search semantics for `<Pkg>Config.cmake` / `Find<Pkg>.cmake`.
  200–400 LOC. The big missing piece for llvm / z3 / torch scale
  corpora; own milestone.
- **`find_program` / `find_path` / `find_library` / `find_file`
  real `$PATH` / `HINTS` / `PATHS` search.** Today: always-NOTFOUND
  stub ([yelu_cmake_find.ml](../../src/langs/yelu/fragments/yelu_cmake_find.ml)).
  Correct when the target binary is absent (matches fmt's DOXYGEN
  on this host); flips to mismatch on a system that has the tool.
  Plan: probe `$PATH` via `Sys.command "which X"` when names look
  bare; otherwise honor `PATHS`/`HINTS`.
- **`try_compile(…)` / `try_run(…)` real probes.** Today:
  always-FALSE stub
  ([yelu_cmake_try.ml](../../src/langs/yelu/fragments/yelu_cmake_try.ml)) —
  writes `<result_var>=FALSE` to var and `"FALSE"` to cache.
  Safe-direction; matches fmt's `compile_result_unused`. Real
  modeling needs a compiler runner.
- **`file(READ)` / `file(WRITE)` / `file(STRINGS)` / `file(GLOB)`.**
  Per-subcommand callback slots. `file(READ)` is the most
  load-bearing (configure-time templates).
- **`execute_process(…)`.** Today returns result=0 and empty
  output. Full impl needs subprocess runner callback.
- **`configure_file(…)`.** Reads template, substitutes
  `${X}`, writes. Different from include — produces files not
  cache state.

### Done (was on this list, now landed)

- ~~cmake stdlib `Modules/` dir in default `module_path`~~ — wired
  via `Cmake_bridge.probe_cmake_modules_dir` (lazy probe of
  `${CMAKE_ROOT}/Modules` via `cmake -P`); fallback to
  `/usr/share/cmake-4.3/Modules`. Done as part of the original
  include() loader work.
- ~~`add_subdirectory(dir)` recursion~~ — `subdir_loader` callback,
  `push_frame` for directory scope, soft-fail on eval errors inside
  subdirs.
- ~~`return()` in functions~~ — `ECmakeReturn` bridged from
  `C.Return`; raises `Return_function` caught by function eval.

### Bool literal handling (Y17 follow-up)

`bool_literal_of_string` in `yelu_cmake_from_emit.ml` is the
single source of truth for parse-time recognition of cmake bool
spellings (case-insensitive). Eval-time coercion lives in
`expect_bool` (yelu_cmake.ml). The dual-site arrangement is
cmake-tolerance, not principled — see `io_architecture.md` § 8
for the migration path to eval-side-only as part of Y17.

### Known bug: `ylet` alias chain (`EVar→EString` demotion)

`ylet` blanket-demotes `EVar n` to `EString n`
([`yelu_cmake_utils.ml`](../../src/langs/yelu/yelu_cmake_utils.ml) `ylet`), so a
chained alias (`ylet "alias" (yvar "name")`) binds to the literal string
`"name"` instead of recursively resolving the prior binding. The
`ylet chain` test is commented out at
[`test_yelu_compile.ml:149`](../../test/test-yelu/test_yelu_compile.ml#L149)
because the un-demoted form loops (no cycle detection in `target_arg`/`arg`).
Proper fix needs cycle detection there. Surfaced by the 2026-06-09 code
audit (finding #5); skip landed in `9041558`. `dune test` is green only
because the test is skipped.

### Other

- **Cache residuals** (from the shipped cache + `-D` work, see
  `../worklog/worklog_2026_06.md` § "Cache namespace"):
  - `CACHE … FORCE` precedence over `-D` — `Lang_cmake.Set_cache`
    carries `force : bool` but yc-eval does not yet honor it (real
    cmake: `-D` wins over even `FORCE` for the initial value).
  - `$CACHE{VAR}` explicit-read syntax — not in the IR (only a comment
    in `yelu_cmake.ml`); the normal→cache read fallback covers most uses.
  - Cross-run cache persistence (real `CMakeCache.txt` on disk) — the
    `-D` channel is the single-configure proxy.
- Process-env namespace (`set(ENV{FOO} val)` / `$ENV{FOO}`) — routes to
  a no-op in eval; needs an I/O callback.
- Generator expressions as delayed values (currently flow as
  opaque `EString`s via `Ycs_eval`; real cmake handles them at
  generate time).
- Generator expressions as delayed values (currently flow as
  opaque `EString`s via `Ycs_eval`; real cmake handles them at
  generate time).
- Fragment-owned parser composition.
- `add_subdirectory` binary_dir arg (second positional) — ignored;
  doesn't affect cache prediction.
- `PARENT_SCOPE` from subdir → parent variables — works via the
  function-scope mechanism but not separately tested for the subdir
  path.
- Property scope expansion beyond target (global / source /
  test / cache).
- A purer functional-style function theory parallel to the
  cmake-style one (Y15 design space; revisit after F2 in
  production).
- Property / random testing and formal proof.

## Notes

- Old production AST has no dedicated normal-variable
  `unset(NAME)` constructor. Normal unset-like behavior is
  encoded as `Yvar_set` with an empty value list. Dedicated
  unset constructors exist for cache / env only.
- `target_link_libraries`, `target_include_directories`, and
  `target_compile_definitions` preserve `PRIVATE` / `PUBLIC` /
  `INTERFACE` visibility, but do not model generator expressions
  or full transitive usage requirements yet.
