# Yelu Theory Composition Tracker

Status: tiny composition harness in progress. **Bar #2 (theory breadth lite)
reached** — all 14 production theories have at least a first slice.
**Bar #1 reached for the tutorial:** v1 step1–step12 (root) plus step8_table,
step11_config bridge through tiny; step1, 2, 3, 4, 5, 6, 7, 8_table, 10, 12
configure through real cmake. step6_ctest, step7_math, step8_math, step9,
step11 also bridge (separate cmake tests subsumed by the cumulative step10 /
step12 fixtures). Tier G (orthogonal cleanup) remains. Constructs covered include project +
cxx_standard + configure_file + add_executable + add_subdirectory +
target_link_libraries + target_include_directories + option +
statement-if + compile definitions + target_compile_features +
generator-expression-shaped compile options + add_test +
set_tests_properties (emit-only). **Function definition + apply now
have proper cmake-style dynamic scope (F2 done) — tiny eval
correctly tracks function registration, param binding, scoped variable
restoration, and persistence of non-var effects.** Step6–12 plan out
as the breadth-first tier list under "Next Steps".

This file is the short tracker to update after each step. Durable design context
lives in:

- `doc/yelu_manifesto.md` — project thesis and layered argument
- `doc/yelu_project_overview.md` — full project audit
- `doc/yelu_theory_composition_design.md`
- `doc/cmake_cache_semantics.md`
- `doc/yelu_lang_coverage.md`

## Two-axle model

Work on `yelu_tiny` advances along two independent axles:

1. **Working pipeline coverage** — extend the bridge from the production
   `yelu_cmake` AST through `Yelu1` (cmake-shaped surfaces) so more existing
   programs flow through the tiny core. This is what makes `yelu_tiny`
   eventually replaceable as the production yelu core.
2. **Per-theory refinement** — develop each `yelu_theory_*` (the Yelu2 ideal
   shape) and lift/lower between it and the matching `yelu_surface_cmake_*`
   (Yelu1 cmake-shaped). This is where each theory's invariants and checks
   eventually live.

Most concrete steps advance axle 1. Refinement work (axle 2) is mostly
deferred until tiny is in a "complete role" (see "Complete role" below).

## Direction

Use `yelu_tiny` as the theory-composition research harness instead of first
refactoring the production `yelu_cmake` pack.

Core migration model:

```text
Yelu1 = tiny core + CMake-shaped surfaces
Yelu2 = tiny core + better/pure Yelu theories

new Yelu code reuses CMake backend:
  Yelu2 -> Yelu1 -> CMake

existing CMake-shaped code can be modernized:
  yelu_cmake AST -> Yelu1 -> Yelu2 -> Yelu1 -> CMake
```

Keep the production parser/compiler/test suite as the compatibility baseline:

```text
src/langs/yelu/lang_yelu_parse.ml
src/langs/yelu/lang_yelu_compile.ml
test/test-runcmake/test_runcmake_yelu.ml
```

Retirement target:

```text
before broad bridge coverage:
  src/langs/yelu_tiny = new theory-composition harness
  src/langs/yelu      = production/legacy CMake-oriented language

after broad bridge coverage and test parity:
  src/langs/yelu      = promoted theory-composition language
  src/langs/yelu_legacy = old production CMake-oriented language
```

Do the rename only after the bridge can route enough old `yelu_cmake` programs
through Yelu1/Yelu2 and the existing production CMake test corpus still passes.

## Current Implementation

Main files:

```text
src/langs/yelu_tiny/yelu_tiny.ml            (* IR, env, core constructors *)
src/langs/yelu_tiny/yelu_tiny_yelu1.ml      (* Yelu1 evaluator *)
src/langs/yelu_tiny/yelu_tiny_yelu2.ml      (* Yelu2 evaluator *)
src/langs/yelu_tiny/yelu_tiny_translate.ml  (* lift / lower + public API *)
src/langs/yelu_tiny/yelu_tiny_cmake_emit.ml (* emit with env-resolve *)
src/langs/yelu_tiny/yelu_cmake_to_yelu1.ml  (* bridge from old AST *)
src/langs/yelu_tiny/fragments/              (* per-theory + per-surface modules *)
```

The split between Yelu1 / Yelu2 / translate emerged once the original
[yelu_tiny_eval.ml] grew past 900 lines mixing four responsibilities;
keeping the evaluators isolated makes it easy to see which fragments
contribute to which bundle. The public symbols [eval_yelu1_expr],
[eval_yelu2_expr], [lift_yelu1_to_yelu2], [lower_yelu2_to_yelu1] all
live in [yelu_tiny_translate.ml] (which depends on both evaluators).

Tests:

```text
test/test-yelu/yelu_tiny_test_helpers.ml
test/test-yelu/test_yelu_tiny_lift_lower.ml
test/test-yelu/test_yelu_tiny_bridge.ml
test/test-yelu/test_yelu_tiny_steps.ml
test/test-yelu/test_yelu_tiny_emit.ml
test/test-yelu/test_yelu_tiny_function.ml
test/test-yelu/test_yelu_cmake_parse.ml
test/test-runcmake/test_yelu_tiny_cmake.ml
```

Implemented tiny fragments:

| Area                 | Status                                                                                                                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core                 | Open `expr`, literals, `EVar`, `ESetVar`, `EUnsetVar`, `ESeq`, `VUnit` effects, `ELet { var; value; body }` (compile-time, lexically-scoped, immutable; option-A canonical let-expression)        |
| Store                | Pure `EUnsetVar`/`EVarDefined`; CMake `ECmakeUnsetVar`/`ECmakeVarDefined`/`ECmakeOption`                                                                                                          |
| Bool/if              | Shared bool ops; CMake statement-if; Yelu expression-if                                                                                                                                           |
| Int                  | Add, less-than, equality                                                                                                                                                                          |
| String               | CMake output-var string ops and pure string ops                                                                                                                                                   |
| List                 | Pure list literal/append/get/length and CMake named-list ops                                                                                                                                      |
| Path                 | First path slice: set, filename, normalize                                                                                                                                                        |
| File                 | First file-effect slice: abstract fs store plus `file(WRITE)`, `file(READ)`, `EXISTS` predicate, and `configure_file(input output)` (tiny copies content as-is, no `${var}` substitution)         |
| Target Layer A       | `add_executable`, `add_library`, target value, `TARGET` predicate                                                                                                                                 |
| Target Layer B       | `target_sources`, `target_link_libraries`, `target_include_directories`, `target_compile_definitions`, `target_compile_options`, `target_compile_features`, `target_link_options`, `target_link_directories` with visibility |
| Build Layer C        | `add_custom_target` and `add_custom_command(OUTPUT ...)` with build-backed execution check                                                                                                        |
| Install              | First slice: `install(TARGETS ...)` and `install(FILES ...)` with temp-prefix install check                                                                                                       |
| CMake op             | First slice: `cmake_minimum_required(VERSION ...)`, `project(name [VERSION ...] [LANGUAGES ...])`, `message([MODE] "...")` with env state for project / cmake_min_version / messages                            |
| Dir                  | First slice: `add_subdirectory(path)` recorded in env.subdirectories; cmake-backed configure with a real subdir/CMakeLists.txt fixture                                                            |
| Test                 | First slice: `enable_testing()` + `add_test(NAME ... COMMAND ...)`; env state for testing_enabled flag and tests list                                                                             |
| Property             | First slice: `set_target_properties(target PROPERTIES key value)` and `get_target_property(var target property)`; env.target_properties as nested map; round-trip with cmake                      |
| Find                 | First slice: `find_package(Name [REQUIRED])` recorded in env.find_packages; cmake-backed non-required configure                                                                                   |
| Try                  | First slice: `try_compile(result_var SOURCES path)`; eval stubs result_var to true; cmake-backed test runs real probe with a tiny C source                                                        |
| File API graph check | Reference CMake vs Yelu-lowered target graph comparison started                                                                                                                                   |
| Runtime env          | Structured `{ vars; targets }` env; target state no longer uses reserved var keys                                                                                                                 |

Current bridge from production AST to Yelu1 covers representative slices for:

```text
string, store-defined, list, path, file write/read/exists,
target add_executable/add_library/existence,
target_sources, target_link_libraries, target_include_directories,
target_compile_definitions, target_compile_options,
target_link_options, target_link_directories,
add_custom_target, add_custom_command,
install_targets, install_files,
cmake_minimum_required, project, message,
add_subdirectory,
enable_testing, add_test,
set_target_properties, get_target_property,
find_package,
try_compile,
configure_file
```

## Production Theory Coverage Dashboard

Counts are coarse constructor counts from the old production fragments under
`src/langs/yelu/fragments`. They are useful for progress tracking, not a formal
coverage metric. `Conf` means configure-time and should usually have a tiny
interpreter. `Build` means it declares build graph behavior. `Install` mutates
only when `cmake --install` runs.

| Production family      |              Old constructors | Phase                     | Tiny status                                     | Theory shape                                                             | Test strategy / notes                                                                                                                                                                           |
| ---------------------- | ----------------------------: | ------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core expr/cond/control |   ~29 expr + ~16 stmt/control | Conf                      | Partial                                         | Mostly pure expression + statement sequencing                            | Bool/if/store subset covered. Many CMake condition predicates remain old-only.                                                                                                                  |
| Var/store              |                             6 | Conf                      | Partial                                         | State theory over variable namespace                                     | Normal set/unset/defined covered. Cache/env/parent-scope deferred.                                                                                                                              |
| String                 | 23 string stmts + JSON subops | Conf                      | Partial                                         | Good pure theory after lifting; CMake surface is output-var sugar/effect | Concat/upper/replace/len/equal covered. Regex/json/timestamp/uuid/etc. deferred.                                                                                                                |
| List                   |                            17 | Conf                      | Partial                                         | Good pure list theory after lifting; CMake surface mutates named vars    | Append/get/length/join covered. Transform/filter/sort/removal variants deferred.                                                                                                                |
| Path                   |                            21 | Conf                      | Partial                                         | Emerging path theory, currently mostly string path normalization         | Set/get-filename/normal-path covered. More path algebra still valuable.                                                                                                                         |
| Target                 |                            19 | Mixed Conf/Build          | Strong representative                           | Stateful build graph theory, not pure value theory                       | Executable, library, target existence, sources, include dirs, link libs, compile/link opts/dirs/defs, custom target/command covered. Alias/deps/PCH/custom-command-target deferred.             |
| Install                |                             6 | Install                   | First slice                                     | Declaration theory over install rules                                    | Targets/files covered with temp-prefix install + manifest path checks. Export/package config deferred.                                                                                          |
| Test / CTest           |                             2 | Build/test                | First slice                                     | Test graph declaration theory                                            | `enable_testing()` + `add_test` covered with env state and configure-mode test. Real `ctest` invocation deferred until bar #1 needs it.                                                          |
| Property               |                            11 | Mixed                     | First slice                                     | Dynamic string-keyed property store                                      | `set_target_properties` and `get_target_property` covered with nested-map env. Real cmake set/get round trip verified. Define-property and global/source/test scopes deferred.                  |
| File                   |                            15 | Conf filesystem effect    | First slice                                     | Abstract fs-store theory keyed by path values                            | `file(WRITE)`, `file(READ)`, and `EXISTS` covered with semantic bridge tests and a temp-script CMake-backed check. Configure/copy/glob/remove/etc. deferred.                                     |
| Find                   |                             5 | Conf environment/probe    | First slice                                     | Probe theory over filesystem/search paths                                | `find_package(Name)` declaration covered. Cmake-backed configure with non-REQUIRED package verified. CONFIG mode, version, components, find_program/library/path/file deferred.                |
| Try                    |                             2 | Conf + build probe        | First slice                                     | Probe theory that runs compiler/build checks                             | `try_compile(result_var SOURCES path)` covered. Eval stubs result_var to true; real `try_compile` runs in cmake-backed test with a tiny C source. `try_run` and extras deferred.                |
| CMake op               |                            14 | Mixed                     | First slice                                     | Misc control/effect surface                                              | `cmake_minimum_required`, `project`, `message` covered with env state (project / cmake_min_version / messages list). `execute_process`, `math`, `cmake_language`, `policy_set`, `include_guard` deferred. |
| Dir                    |                             8 | Build/config scope        | First slice                                     | Directory-scope mutation theory                                          | `add_subdirectory(path)` covered with env state and a real subdir/CMakeLists.txt fixture. Directory-scoped compile/link/include commands deferred. Subdir scope semantics not yet enforced.    |
| Genex                  |               ~17 genex forms | Build-time delayed values | Lexer/parser fixed, not a tiny theory           | Delayed expression theory, not configure-time pure                       | Should become a delayed-value type later; do not force into normal interpreter now.                                                                                                             |

Useful interpretation:

- **Pure-ish theory wins:** string/list/path once lifted out of CMake's
  output-variable surface.
- **State/declaration theories:** target, install, test, property, dir.
- **Probe theories:** find and try. These are configure-time, but their tests
  need controlled temp fixtures rather than pure semantic evaluation.
- **Delayed build-time theory:** generator expressions. They should not be
  evaluated by the configure-time interpreter.

## Verification Status

Current check commands:

```sh
eval $(opam env) && dune test test/test-yelu/
eval $(opam env) && dune exec test/test-runcmake/test_yelu_tiny_cmake.exe
```

Last verified state:

```text
test/test-yelu/ passed (tiny split suites: 134 tests
  = 43 bridge + 65 lift_lower + 3 emit + 10 steps + 13 function)
test_yelu_tiny_cmake passed with 36 tests
```

Verification tracks:

| Track                   | Current status | Rule                                                                                  |
| ----------------------- | -------------- | ------------------------------------------------------------------------------------- |
| Semantic equivalence    | Active         | Compare final `env` and final `value` for Yelu1/Yelu2/lift/lower                      |
| Parser bridge           | Active         | Parse production syntax -> old AST -> Yelu1 -> evaluator                              |
| CMake-backed checks     | Active         | Add at least one CMake-backed case for each new CMake surface                         |
| Install safety          | Active         | Run installs only into temp prefixes; assert install manifest paths stay under prefix |
| Constructor coverage    | Manual         | Keep adding focused examples as constructors are added                                |
| Property/random testing | Later          | Add after core/target env settles                                                     |
| Formal/SMT proof        | Later          | Consider only after tiny core and key theories stabilize                              |

## Current Design State

The interpreter env mixes state belonging to different cmake phases.
Today it is kept flat for evaluation simplicity; the comment groups in
[yelu_tiny.ml] mark the intended phase so a future refactor can move
each field next to its own theory module (and possibly into
phase-distinguished records). The four conceptual groups are:

**Configure-time: script state.** Read/written while the cmake script
itself executes.

```text
env.vars:
  normal Yelu/CMake variables. Doubles as the home for ELet lexical
  bindings via save/restore — a known conflation; a future split could
  give let bindings their own namespace separate from cmake's mutable
  set() variables.

env.files:
  abstract configure-time filesystem store, keyed by path strings.
```

**Configure-time: declarations / diagnostics.** Records of what the
script said; used as oracle state to verify behavior, not consumed by
cmake the tool.

```text
env.project / env.cmake_min_version:
  set-once project metadata from project(...) and
  cmake_minimum_required(VERSION ...).

env.messages:
  declaration-order log of message([MODE] "...") calls.

env.subdirectories:
  declaration-order log of add_subdirectory(path) calls. Subdir scope
  semantics not yet enforced.

env.includes:
  declaration-order log of include(FILE_OR_MODULE) calls. Tiny does
  not recursively evaluate included content; real cmake handles the
  module / file loading at configure time.

env.find_packages:
  declaration-order log of find_package(Name [REQUIRED]) calls.

env.try_compiles:
  declaration-order log of try_compile calls; eval stubs result_var to
  true (the real probe runs only when the lowered cmake script runs).
```

**Build-time: target graph + test graph.** Declared at configure-time
but materialized when the build runs.

```text
env.targets:
  target declarations and target-local metadata (sources, links,
  include dirs, compile defs / opts, link opts / dirs, etc.).

env.custom_targets:
  named build entrypoints from add_custom_target.

env.custom_commands:
  build-time output rules from add_custom_command(OUTPUT ...), keyed
  by primary output path.

env.target_properties:
  nested map (target -> property -> value) for set_target_properties /
  get_target_property.

env.testing_enabled / env.tests:
  set-once flag from enable_testing() plus declaration-order list of
  add_test(NAME ... COMMAND ...) decls.
```

**Install-time: deferred actions.**

```text
env.install_rules:
  configure-time install declarations, preserving target/file inputs
  and relative install destinations. Run only by cmake --install.
```

Target state currently tracks sources, link libraries, include directories,
compile definitions, compile options, link options, and link directories as
visibility-aware records. The visibility-list helpers
(`update_existing_target ~f`, `eval_string_list`,
`eval_target_visibility_items`) collapse the per-property add helpers and
eval cases so that adding a new Layer B property is roughly five lines per
mutation point. Custom commands live in their own env namespace so the
build-rule shape (outputs as paths, deferred command execution) does not
mix with target-mutation state.

## Theory invariants — the point of the split

The payoff of splitting `yelu_cmake` into `yelu_theory_*` + `yelu_surface_cmake_*`
modules is not code organization. It is that each theory becomes the home for
its own semantic invariants. Today most invariants live as English in commits
and design notes; the long-run target is to have them *in the module*. Concrete
examples already encountered:

- A **target** has a logical name in target-namespace; its state is mutated
  across many statements (`target_sources`, `target_link_libraries`, …).
- A **custom_target** has a name in custom-target-namespace and is
  set-once at declaration.
- A **custom_command** is keyed by **filesystem output path**, not name; its
  state is set-once; multiple commands cannot legally claim the same output.

Each of these is a distinct sub-theory with distinct namespace, mutability,
and identity rules. The `env` already encodes the namespace separation
(distinct `Map.M(String).t` per kind). The mutability and identity rules
are still informal. When we eventually bring `Stage_typecheck` and
`Stage_wellform` over to tiny, those invariants are what the checks operate
on. Avoid encoding them in `eval` — eval is the wrong layer.

Corollary for adding new constructors: ask first which sub-theory the
constructor belongs to, what its namespace is, and whether it is set-once or
mutable. Decide that before writing the eval case.

## Checking passes are deferred

The production `yelu_cmake` has `Stage_typecheck` (per-theory) and
`Stage_wellform` (whole-program name binding). Both are deferred for the
tiny core. Reasoning: the right time to add them is *after* the tiny core
covers a "complete role" (see below), because the choice of constructors,
env shape, and lift/lower compositions is harder to undo than a missing
check is to add later. Until then, expect:

- Eval-time exceptions (`Eval_error _`) instead of structured diagnostics.
- Visibility values are raw strings (`"PUBLIC"`/`"PRIVATE"`/`"INTERFACE"`),
  not a typed sum.
- Some collisions silently overwrite (e.g. two `add_custom_command` calls
  with the same OUTPUT) — a future wellform pass catches them.

This is documented gap, not technical debt. New work should *not* try to
patch checks into eval; it should accumulate constructor coverage first.

## Complete role — the milestone framing

Three candidate bars, in increasing ambition. We work toward them in order;
each bar is a meaningful checkpoint.

| Bar                          | Definition                                                                                                                                                                                                                                                | What it proves                                                                                    |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **#1 Tutorial step parity**  | `yelu_tiny` lifts/lowers everything used by tutorial v1 steps 1–12 (the existing `make stepN` end-to-end suite).                                                                                                                                          | Tiny is real enough to compile a non-trivial cmake project end-to-end.                            |
| **#2 Theory breadth (lite)** | Tiny has a representative slice for each of the 14 production theories: var, target, install, test, property, string, file, path, list, find, try, cmake_op, cond, dir. Slice = the smallest observable workflow with bridge + lift + lower + cmake emit + tests. This may be one constructor, or a producer/consumer pair when isolated commands are not meaningfully observable. | The theory-splitting architecture composes across all domains, not just the ones already covered. |
| **#3 Bridge parity**         | Every `yelu_cmake` constructor exercised by `test_yelu_compile.ml` (194 tests) bridges through tiny.                                                                                                                                                      | Production test corpus passes through tiny → the rename `yelu_tiny` → `yelu` becomes feasible.    |

Recommended arc: **#1 → #2 (lite) → #3**. Once #3 is green, axle 2 work
(checking passes, refined theory shapes, typed visibility, etc.) becomes
the next chapter.

## Next Steps

**Bar #2 (theory breadth lite) reached.** All 14 production theories now
have at least a first slice through tiny. Genex stays deferred (delayed
build-time values, separate research thread).

**Bar #1 first milestone:** tutorial v1 step1 program now both bridges and
configures through real cmake end-to-end. **Step2/Step3 milestone:** tutorial
v1 step2 and step3 root/math programs plus step4 root now bridge and
configure through real cmake. Root tests still use a minimal direct-CMake
`MathFunctions` subdirectory fixture; the math subdirs are emitted from tiny.
The work surfaced these deepening points:

- `cmake_minimum_required` accepts a max version range (`3.20.0...3.20.0`);
  bridge currently drops the max.
- `project(... VERSION ...)` accepted; version threaded through env state.
- `configure_file(input output)` — first slice in file theory.
- **`ELet` added as a core control-side feature.** Tiny's IR now has a
  proper compile-time, lexically-scoped, immutable let-binding
  (option A: canonical let-expression with an explicit `body`). Distinct
  from `ESetVar`, which models cmake's mutable global `set()`. The two
  binding mechanisms coexist (per Y15 design intent: lexical/immutable
  vs global/mutable). The bridge converts production `Ylet` (sequence-shaped)
  into `ELet { body = rest_of_seq }` via `stmts_to_expr`.
- **Phase 2a — let-binding emit-time resolution (done).** `emit_expr`,
  `arg`, and `cond` now thread a substitution env. `ELet` extends env
  before recursing into body and is dropped from the output; `EVar`
  references that the env knows about resolve to the bound value at emit
  time (transitively, lazily on lookup) instead of emitting `${name}`.
  The architecture is the "fold into emit" choice — no separate resolve
  module, `ELet` stays first-class in the IR (eval still uses it; future
  Stage_wellform can check shadowing; future yelu2→other-target packs
  inherit the same letful IR and write their own emit-with-substitution).
  Cmake-backed test verifies real cmake sees the substituted value.
- **Phase 2b — surface target-name refactor (done).** All target-name
  fields in surface constructors (`ECmakeAddExecutable`, `ECmakeAddLibrary`,
  `ECmakeTarget*`, `ECmakeAddCustomTarget`, `ECmakeTargetExists`,
  `ECmakeSetTargetProperty`, `ECmakeGetTargetProperty`,
  `ECmakeInstallTargets.targets`) now take `expr` instead of `string`.
  Theory side updated to match (`ECustomTarget.name`, `EGetTargetProperty.target`).
  Bridge `target_name` is now an alias for `expr` — it returns the raw
  `EVar` / `ETarget` / `EString` form so let-bindings can flow through.
  Emit gained a `target_arg` helper that consults the substitution env
  (like `arg`) but renders unquoted (cmake target names are conventionally
  unquoted). `expect_string` and `expect_target` now coerce between
  `VString` and `VTarget` so a target name is interchangeable with a
  string in eval contexts. **Result:** step1 now emits
  `add_executable(Tutorial "tutorial.cxx")` and
  `target_include_directories(Tutorial PUBLIC ...)` matching production
  yelu output; the spurious `set(tut "Tutorial")` is gone.

Next we work toward **bar #1 (tutorial step parity)** and **bar #3 (bridge
parity)** roughly in parallel:

- **Bar #1 path:** drive yelu_tiny through tutorial v1 steps 1–12 via the
  bridge from existing `src/bin/yelu/v1/stepN.ml` programs. Each step that
  fails to bridge identifies a missing constructor; deepen the relevant
  theory just enough to unblock. This is the most direct way to surface
  what's actually used vs. what's nice-to-have.
- **Bar #3 path:** drive `test_yelu_compile.ml` (194 tests) through tiny
  one suite at a time. Each failing test names a missing constructor or
  shape. Same pattern — deepen as needed, no speculative coverage.

### Steps achieved (Bar #1)

- **Step1** — bridges and configures equivalently to production
  `yelu_compile` output.
- **Step2 root + math** — bridge + cmake-backed configure. Added first
  `option(...)` slice; validates statement-if lowering through real CMake.
- **Step3 root + math** — bridge + configure. Added
  `target_compile_features`; validates the
  `tutorial_compiler_flags` interface-library pattern.
- **Step4 root** — bridge + configure. Existing
  `target_compile_options` handled the compiler-warning block,
  including genex-shaped strings such as `$<${gcc_like_cxx}:...>` and
  `$<BUILD_INTERFACE:...>`. Step4 math has bridge but not configure
  (pending compile_definitions in custom-target arguments).
- **Step5 root + math** — bridge + configure pass. **F2 function theory
  is done:** `function()` and `apply` definitions now register in
  `env.functions`, applications bind params, evaluate the body under
  cmake-style dynamic scope, and restore vars on return. Step5's `test_suite`
  function calls are now correctly simulated end-to-end (not just
  emit-correct). Dedicated theory-expansion tests live in
  `test/test-yelu/test_yelu_tiny_function.ml`.

### Breadth-first tier list for steps 6–12

Each tier is the smallest representative slice that gets the step to
bridge + configure through real cmake. We don't simulate runtime
semantics deeply unless eval-side tests fail. Follow the pattern that
worked for steps 1–5: bridge first, configure-test second, then
strengthen eval as needed.

| Tier | Target step(s) | New work |
| --- | --- | --- |
| **A** ✓ | step6, step6_ctest | `include(FILE_OR_MODULE)` — first slice: records name in `env.includes`, emits `include("FILE")` (with `OPTIONAL` suffix when set). Step6 root + step6_ctest now bridge; step6 root also configures through real cmake. |
| **B** ✓ | step7, step7_math | Two pieces: (a) bridge keeps `EVar` / `Yexpr_name` in `yc_function` / `yc_apply` name position so ELet substitution at emit can resolve let-bound function names (was `command_name` short-circuit; now `expr`); (b) surface `ECmakeApply` evaluates lenient — unknown functions return `VUnit` after evaluating args, since cmake routinely calls bodies loaded via `include(SomeModule)` that tiny does not simulate. Theory `EApply` stays strict. New `let_value` bridge rule maps `ycstr name` (= `Yexpr_name {ns=Ns_var; name}`) to `EString` in let-value position so `ylet "x" (ycstr "x")` and `ylet "x" (ycstr "literal")` don't create self-cycles or unintended derefs. step7 root + step7_math now bridge; step7 root configures through real cmake. |
| **C** ✓ | step8_table, step8_math | step8_table uses the OUTPUT form of `add_custom_command` (already bridged via `Ytgt_add_custom_command`); the TARGET-form sibling `Ytgt_add_custom_command_target` remains deferred (no v1 step uses it). step8_math composes Tier A's `include()` with a generated source path. Both bridge with no new fragment work; step8_table also configures through real cmake. |
| **D** ✓ | step9, step10 | `cpack_basic` (sequence of `yc_set` + `include(CPack)` + `include(InstallRequiredSystemLibraries)`) and `shared_libs_output_dirs` (three `CMAKE_*_OUTPUT_DIRECTORY` sets + `BUILD_SHARED_LIBS` option) compose from already-bridged pieces. No new fragment work; step10 configures through real cmake. |
| **E** ✓ | step11_config | `yc_at_var key` added: theory `EAtVar of string` + surface `ECmakeAtVar`, eval is a no-op (literal is substituted later by `configure_package_config_file` over a `.cmake.in` template), emit renders `@key@` as a bare line. Bridge + lift/lower wired. step11_config bridges. (step11 full root waits on Tier F.) |
| **F** ✓ | step11, step12 | Package-config family: theory + surface constructors `EInstallExport` / `EExportExport` / `EConfigurePackageConfigFile` / `EWriteBasicPackageVersionFile` plus matching env install_rule variants. Bridge wired (production AST now exhaustively matched — no catch-all). Lift/lower paired on both axes. Emit follows the production cmake pretty-printer (FILE / NAMESPACE / NO_SET_AND_CHECK_MACRO / NO_CHECK_REQUIRED_COMPONENTS_MACRO / VERSION / COMPATIBILITY / ARCH_INDEPENDENT). step11 + step12 bridge; step12 also configures through real cmake (the configure test's fixture adds `install(TARGETS MathFunctions EXPORT MathFunctionsTargets ...)` so the export set is declared). |
| **G** | orthogonal cleanup | `ECmakeOption` eval through `eval` (currently ad-hoc match); `ECmakeSetTestsProperties` eval through a new env namespace; `set_property(TARGET ...)` as older sibling of `set_target_properties`. |

Total: roughly 7–10 incremental slices, each 30–100 lines. None large
individually.

### The function theory (F2 — done)

`EDynFunction` / `EApply` (theory) and `ECmakeFunction` / `ECmakeApply`
(surface) are now first-class core constructs with proper semantics.

**Decisions, all in place:**

- **First-class control-side feature.** Functions live in the tiny core
  next to `ELet`, available to all packs (not just the cmake-pack).
  This opens the door later to a cmake `macro()` slice (textual
  substitution; different lifecycle) and to a separate functional-style
  function theory whose scope design we haven't yet settled.
- **Argument evaluation:** left-to-right, call-by-value (args fully
  evaluated before the function body runs).
- **Scope: classic dynamic scope via shallow binding** (the canonical
  PL terms; Bobrow & Wegbreit 1973, EOPL). On function entry the
  entire current variable scope is saved; params are bound as fresh
  vars; the body is evaluated in the extended env; on return the saved
  variable scope is restored. Variable *reads* inside the body see the
  caller's scope (dynamic-scope semantics); variable *writes* are
  local to the call frame (cmake's "writes local by default" wrinkle —
  contrast with bash where writes leak). *Side effects on non-variable
  env state (targets, tests, install_rules, custom_targets,
  target_properties, messages, …) persist across the call.*
- **Macros and ARGV/ARGC:** deferred. `macro()` is textual substitution
  with no scope frame; `ARGV` / `ARGC` / `ARGN` are positional argument
  reflection. Neither is needed for tutorial step parity in v1 of the
  cmake tutorial; record them and revisit if step tests fail.

**Implementation pointers:**

- `function_decl = { params : string list; body : expr }` lives in
  [yelu_tiny.ml]; equality is manual (the body is the open expr).
- `env.functions : function_decl Map.M(String).t` is in the
  configure-time script-state group, with helpers `set_function`
  / `find_function`.
- Eval lives in both [yelu_theory_cmake_op.ml] (EDynFunction/EApply)
  and [yelu_surface_cmake_cmake_op.ml] (ECmakeFunction/ECmakeApply).
  They share the same scope mechanics via local `bind_params` /
  `eval_args` helpers. The constructor name `EDynFunction` (rather
  than the unmarked `EFunction`) reserves the unmarked name for a
  future lexically-scoped / closure-style function.
- Observability gotcha: at the IR level, the function's body is stored
  in different surface forms by Yelu1 (ECmake*) and Yelu2 (E*) — that
  divergence is *behaviorally* irrelevant but breaks strict
  `equal_env`. The dedicated function tests in
  [test_yelu_tiny_function.ml] use side effects on `env.messages` to
  observe function behavior without depending on var leakage or on
  internal storage.

### Retirement track (post-Bar #1)

**Goal.** Glue the existing `yelu_cmake` test surface (step files, parser,
compile, runcmake-yelu pairs) onto the `bridge → tiny → cmake` path so
that retiring `src/langs/yelu/fragments/` becomes the natural next move
once gluing covers every test. Typecheck + wellform port intentionally
postponed; keep tiny fragment distribution aligned with production
fragment distribution so the eventual port stays mechanical.

**Goal status (as of 2026-05-10).** Step files 19 / 51 bridged; bridge
fail-cases 13 catch-alls; `test_yelu_compile` 0 / 194 routed through
tiny; `test_runcmake_yelu` 0 / 50; `test_yelu_parse` 0 / 170; genex
theory has 0 / 34 production constructors mirrored.

Phases, in suggested order. The dependency is mostly demand-driven:
each phase surfaces fail-cases for the next; bridge-fail attrition
(R2) and genex (R3) advance whenever R1/R4/R5/R6 demand them.

| Phase | What | Detail |
| --- | --- | --- |
| **R1** | Step file backfill (32 files) | v1 math: 6/6 ✓. v2 root: 11/11 ✓. CMakeOnly top-level: 11/13 done (project_include, project_include_before, target_scope, target_scope_sib, target_scope_sub, target_scope_sub_sub, fetch_content, link_interface_loop, major_version_selection, find_path, select_library_configurations). 2 remain: find_library + all_find_modules — both need string-regex-replace + (for all_find_modules) foreach control flow + file_glob. 2 files in this dir are debug binaries (debug_genex, debug_kwarg) and not bridgeable. **47/49 step programs bridged (96 %).** |
| **R2** | Bridge fail-case attrition | Now added (May 10): `Ytgt_add_library_alias`, `Ytgt_add_executable_alias`, `Ytgt_add_dependencies`, `Ytgt_sources_fs` (FILE_SET), `Ytgt_precompile_headers`, `Ytgt_add_library_imported`, `Yprop_set`, `Yfind_package` (relaxed pattern), `Yexpr_ver_*`, `Ycmake_math`, `Yc_macro`, `Yvar_unset_cache`, `Yfile_relative_path`. Remaining demand-driven from R1's last 2 files + R4/R5/R6: `Ypath_get_filename_component`, `Ystr_regex_replace` / `Ystr_regex_match*`, `Yfile_glob`, `Yc_foreach` / `Yc_foreach_in`. The control-flow constructs (foreach) are a separate slice — closer to F2 in spirit. |
| **R3** | Genex theory | Net-new theory. Production has 34 constructors; tiny has 0. First slice is the few generator expressions v2 / CMakeOnly steps actually use (`$<CONFIG:...>` etc.); rest deferred. |
| **R4** | Glue `test_yelu_compile` (194 tests) | Mirror each compile test against `bridge → tiny → emit`. Compare structurally to production cmake output (gersemi or text-eq mod whitespace). Drives R2 hard. |
| **R5** | Glue `test_runcmake_yelu` (50 pairs) | Drive tiny-emitted scripts through cmake `-P` (or configure) and compare against the same reference. |
| **R6** | Glue `test_yelu_parse` (170 tests) | Parser already produces production AST → bridge it. Each parser test becomes a bridge test too. |
| **R7** | (postponed) typecheck + wellform port | Carry over the 14 `Make_*_check` modules and the wellform pass to tiny. Defer until R1–R6 stabilize the fragment distribution so the port is mechanical. |

**Retirement criterion.** `src/langs/yelu/fragments/` is retirable when:
- (R1) all 51 step files bridge.
- (R2) zero `_ -> fail` cases remain in the bridge.
- (R4 + R5 + R6) production tests run through tiny with equivalent
  cmake output / configure success.
- (R7) typecheck + wellform exist in tiny so the production checker
  module can be removed.

At that point `src/langs/yelu_tiny/` becomes the production code and
`src/langs/yelu/` (sans parser, lexer, post-bridge stages) becomes
`src/langs/yelu_legacy/` per the original direction.

### Skip-for-now (axle 2)

- `Stage_typecheck` / `Stage_wellform` passes on the tiny core.
- Typed visibility, typed library kind.
- Generator expressions as delayed values (currently flow as opaque
  `EString`s via `Ycs_eval`; real cmake handles them at generate time).
- Fragment-owned parser composition.
- Subdirectory scope enforcement (currently `add_subdirectory` records
  but does not isolate var/target scopes).
- Property scope expansion beyond target (global / source / test / cache).
- `set(VAR value CACHE ...)` cache semantics — `option(...)` first slice
  records value as a normal var.
- A purer functional-style function theory parallel to the cmake-style
  one (Y15 design space; revisit after F2 is in production).

## Deferred Topics

- Cache/env namespaces beyond the current normal-variable store slice.
- `PARENT_SCOPE`.
- Generator expressions as delayed values.
- Build-time artifacts and custom command bodies (beyond the
  `add_custom_command(OUTPUT ...)` slice already implemented).
- Fragment-owned parser composition.
- Type annotations and a later `yelu_tiny_typed`.
- Property/generated testing and formal proof.
- `Stage_typecheck` and `Stage_wellform` passes on the tiny core
  (intentionally deferred — see "Checking passes are deferred").

## Notes

- Old production AST has no dedicated normal-variable `unset(NAME)` constructor.
  Normal unset-like behavior is encoded as `Yvar_set` with an empty value list.
  Dedicated unset constructors exist for cache/env only.
- `target_link_libraries`, `target_include_directories`, and
  `target_compile_definitions` currently preserve `PRIVATE`/`PUBLIC`/`INTERFACE`,
  but do not model generator expressions or full transitive usage requirements
  yet.
