# yelu_cmake — Status & Current Open Work

This doc tree (`doc/yelu_cmake/`) is cmake-language-specific.
Any future `yelu_shell` / `yelu_c` work would get its own
sibling tree.

Living tracker. Strip and update freely; durable design is in `design.md`,
code-anchored module guide in `structure.md`, history in
`../worklog_2026_04.md` / `../worklog_2026_05.md`.

## Where we are (2026-05-14)

**Retirement is complete through E1: `yelu_legacy/` is
deadcode.** Production binaries generate cmake text via
`Yelu_cmake_utils → Yelu_cmake → Yelu_cmake_emit →
Lang_cmake_pp` with no calls into the legacy bridge. The two
languages — `yelu_cmake` (CMake-faithful) and
`yelu_cmake_normal` (normalized form) — have clean names
throughout `src/langs/yelu/`; the legacy stack lives in
`src/langs/yelu_legacy/` and is excluded from the `yelu_langs`
library via the parent dune's `(modules :standard \ …)`. The
modules stay on disk for reference but no longer compile into
anything.

**Verifications** (continuously green):
- `dune build && dune test` — 1010 unit tests pass
- parser tests: 280 (after dropping 15 legacy-only inputs in
  E1; the new parser does not yet handle `~msg:`, `~global`,
  alias commands, custom targets, foreach IN, block, extern,
  set_env, etc.)
- `make cmake-only-check`: 12/12
- `make runcmake-yelu`: 50/50
- `make cmake-commands` was broken pre-E1 (`Failure("expected
  target name")` on `a99d9f7`); after E1 it surfaces 12 cmake
  build-level failures (`-PRIVATE_FLAG` rejected by `cc`) that
  are pre-existing, not regressions

**Retirement summary** (all done):
- Phase 1: production text generation routes through `emit_ast`
  → `Lang_cmake.exp` → `cmake_pp`
- Phase 2a: separate parser (`Yelu_parse`) covers all 12
  families directly to Yelu1 IR; byte-identical to the bridge
  path on every covered test
- Phase 2c: legacy compile/wellform/type/utils + 15 fragments
  relocated to `src/langs/yelu_legacy/`
- Item A: direct-parser gap list closed
- Item B: genex opaque-string handling sufficient (typed
  theory → Y17)
- Item C: binary callers repointed onto bridge + emit_ast
- E-lite: legacy parser+lexer to yelu_legacy
- Item D: `yelu_tiny` renamed to `yelu`
- E-utils: step files emit IR directly via
  `Yelu_cmake_utils`; bridge off the binary path
- Item G: language-name honesty + legacy isolation —
  `yelu_cmake` / `yelu_cmake_normal` vocabulary anchored
  everywhere; bridge moved to `yelu_legacy/`; enum-string
  converters extracted to `Lang_cmake_strings` in the cmake
  layer; fragments renamed; lexer renamed and relocated
- Item F: parser dispatchers route through `Yelu_cmake_utils`
  (one source of truth for command-shape decisions; −86 LOC in
  `yelu_parse.ml`)
- **Item E1** (2026-05-14, commits `c85fb3d` `d0def93`
  `a99d9f7` `5b11ae7`) — legacy made deadcode:
  - Byte oracle (194 programs in `test_yelu_compile.ml`)
    rewritten to assert new emit path against inline expected
    strings frozen from the legacy reference
  - Pair-wise parser oracle (125 `_y1` cases in
    `test_yelu_cmake_parse.ml`) rewritten the same way
  - `test_yelu_bridge.ml` deleted
  - `test_yelu_check.ml` deleted (its `Cmake_check` typecheck
    pass + `Lang_yelu_wellform` binding pass exist only on the
    legacy AST; replacement covered by Y17)
  - 22 step binaries + their dune setup migrated to
    `Step_common_ir`; legacy `Step_common` deleted; ergonomic
    enum re-exports added to `Yelu_cmake_utils`
  - 26 `test/test-runcmake/*` files migrated off
    `Lang_yelu_compile` to the IR + `emit_ast` path
  - ~150 lines of gap-fills in `Yelu_cmake_utils` (yc_string_*
    family extensions, list_transform, ygreater/yless,
    yc_link_libraries, yc_add_custom_command_target stub, math
    output_format accept-and-discard, separate_arguments
    `?input` shape fix, ystr-comparison stubs)
  - `ECmakeAddCustomCommand` added to `emit_ast`
  - `add_exe` / `add_lib`'s `~exclude_from_all` now silently
    drops rather than failwith'ing
  - `ylet` fixed to demote `EVar n → EString n` at bind time
    (mirrors the legacy bridge's `let_value`; without it
    `ylet "do_test" (ycstr "do_test")` infinite-looped
    `emit_debug.arg`)
  - `src/langs/dune` excludes all 24 yelu_legacy modules from
    the `yelu_langs` library

**Remaining retirement item:**
- **E2** — delete `yelu_legacy/` entirely. Gated on E1 holding
  green long enough and Y17 (typecheck reintroduction) not
  needing legacy as reference.

**Four legacy-parser bugs** surfaced during the migration but
deferred — production tests don't exercise them, and they share
the same shape (handler matches narrow `Yexpr_string` variant
and falls through to `""` / `"?"` for other variants):
- `( set NAME val )` form
- `( policy_set "CMPxxxx" )` form
- `( cmake_call "myfn" )` form
- `( message ${VAR} )` form (drops `Ycs_eval`)
All four omitted from the pair-wise oracle; legacy parser fix
deferred (one-line edit per case).

For the full retirement record (Phase 1, 2a, 2c, items A–G), see
`retirement_plan.md`. For chronological history,
`../worklog_2026_05.md` covers the harness build-out using the older
"Yelu1 / Yelu2 / yelu_tiny" vocabulary.

## Known IR shape gaps (carried into E1)

Constructors the legacy compile path handled but the IR + `emit_ast`
path does not yet model with full fidelity. E1's gap-fills in
`Yelu_cmake_utils` either stub or accept-and-discard the affected
options; tests exercising the missing semantics may still fail at
the cmake-build layer (not the build layer).

- **String-comparison conds beyond equality** — `STRLESS` /
  `STRGREATER` / `STRLESS_EQUAL` / `STRGREATER_EQUAL`. E1 stubs
  `ystrless` / `ystrgreater` / `ystrless_equal` /
  `ystrgreater_equal` as `ECmakeStringEqual`, which compiles but
  changes runtime semantics. 4 cases in `test_if.ml` are affected.
- **`add_executable` / `add_library` with `EXCLUDE_FROM_ALL`** —
  the IR ctors don't carry the flag. E1's `add_exe` / `add_lib`
  silently drop `~exclude_from_all`. Builds still configure; the
  generated targets are no longer excluded from `make all`.
- **`target_link_libraries` multi-target** — bridge supported
  exactly one target per call; production AST allowed multiple.
  The IR surface still takes a single target; multi-target callers
  must split into per-target statements.
- **`add_custom_command(TARGET ...)`** — TARGET-form custom
  command. E1 stubs `yc_add_custom_command_target` as an empty-
  outputs `ECmakeAddCustomCommand`; emit produces a valid but
  semantically degenerate `add_custom_command(...)`.
- **`math` `~output_format`** — IR `ECmakeMath` only carries
  `exp` and `out`. E1's `yc_math` accepts `~output_format` and
  discards it; tests using `Hexdecimal` get decimal output.
- **JSON ops** — `ECmakeStringJson` is opaque
  (`op_name = "JSON_op"`, no path / sub-op detail). The legacy
  bridge already lost this fidelity; E1's `yc_string_json_*`
  helpers match the bridge's collapse rather than the legacy
  compile path's full enumeration.

These are now first-class TODOs for any post-deadcode feature
work; see also `## Post-retirement cleanup` below.

## Y17 — types on yelu_cmake (post-retirement)

The previous typing attempt (production `Stage_typecheck` per
fragment) was structurally shallow: each fragment validated its own
expression types in isolation, with `wellform` bolted on top to
handle cross-theory name binding. With proper theories
(`Yelu_cmake_normal_*`) the type design has actual semantic ground
to stand on — namespace separation is already in `env`,
mutability / set-once / identity rules belong with each theory
module, and `to_normal` / `from_normal` give a natural place to push
richer invariants.

Order: bring types in **after** retirement establishes
yelu_cmake ↔ cmake AST and yelu_cmake_normal ↔ yelu_cmake as a
stable composition. Retrofitting types onto an unstable substrate
would repeat the previous failure mode. Retirement is essentially
done, so Y17 is unblocked from a "stable substrate" standpoint;
sequencing depends on appetite for the design work.

## Post-retirement cleanup

Deferred until after the production switch, in order of value:

1. **Split `cmake_op`** into smaller surfaces (project/message, control
   flow, function/macro, process, policy/include). 390-line surface +
   103-line theory is the largest single fragment and the broadest
   compatibility bucket.
2. **Generated fragment coverage table** — auto-generate a matrix
   (semantics eval, lift, lower, emit, bridge, unit test, cmake-backed
   test) per fragment so coverage gaps stay visible as constructors are
   added.
3. **Move emit / convert arms closer to each fragment.** Currently
   `yelu_cmake_convert.ml` (~1.7 k lines, formerly
   `yelu_tiny_translate.ml`) and `yelu_cmake_emit_debug.ml` (~964 lines,
   formerly `yelu_tiny_cmake_emit.ml`) are central registries — they
   work, but entropy returns here as constructors land. Per-fragment
   convert / emit modules reverse the trend. Cosmetic, not load-bearing;
   defer until after the bigger Y17 typing decisions.
4. **Y17 — fresh typing pass on yelu_cmake** (see "Y17" section above).
5. **Promote compat surfaces to real theories** where they're worth it
   (genex first, then find / try / cmake_op subsets). This pairs with
   Y17 — typing decisions inform which surfaces deserve the lift.
6. **Categorize `yelu_cmake_normal_*` theories: general vs
   cmake-specific.** After the G rename, every fragment on the
   yelu_cmake_normal side wears the cmake prefix, but several are not
   cmake-specific at all — `bool`, `int`, `string`, `list`, `store`
   are general-purpose theories that any future `yelu_*` language
   (`yelu_shell`, `yelu_c`) would also want. They live next to the
   genuinely cmake-specific ones (`target`, `install`, `find`,
   `property`, `try`, etc.) only because the historical
   `yelu_theory_*` bundle didn't distinguish. Cleanup options:
   - Move the general theories to a shared location (e.g.,
     `src/langs/yelu_core/` or similar) callable by any yelu_*
     language.
   - Or just rename them to drop the `yelu_cmake_normal_` prefix
     in-place if they stay co-located (`yelu_theory_bool.ml`? but
     we just abolished `_theory_`).
   - Either way, the principle is that the `yelu_cmake_normal_`
     prefix should mean "specific to the normalized form of cmake",
     not "happens to live in this directory."
7. **Split the shared `expr` type between `yelu_cmake` and
   `yelu_cmake_normal`.** Today both languages use the same
   extensible `Yelu_cmake.expr` type, with each surface fragment
   adding ctors via `type expr += ...`. This means `yelu_cmake`'s
   expr universe technically contains every `yelu_cmake_normal` ctor
   and vice versa — a soft coupling that hides the language
   boundary. A clean separation would give each language its own
   `expr` type, with shared nodes (`EVar`, `EString`, `EBool`,
   `EInt`, `ESeq`, `ELet`, `ESetVar`, `EUnit`) staying in a small
   shared core. Some types currently in `yelu_cmake.ml` (e.g.,
   `target`, `install_rule`, `custom_command`) should likely move
   into their owning theory fragments at the same time. Pairs
   naturally with item 6 (general vs cmake-specific theories) and
   item 4 (Y17 typing).

## Project-level milestones (separate from retirement)

- **Bar #3 — real-world cmake.** Rewrite z3 / llvm / torch builds
  in `yelu_cmake`, prove structural equivalence with the original
  CMakeLists. Not started; the manifesto-level "does this scale"
  test.
- **Macro elimination.** Whether to drop `function()` / `macro()`
  from yelu_cmake in favor of pure-OCaml parameterization, given
  yelu programs are themselves OCaml. Deferred; revisit with
  Bar #3 data. Memo: `.claude/memory/project_macro_elimination.md`.

## Deferred

- Cache / env namespaces beyond the normal-variable slice.
- Generator expressions as delayed values (currently flow as opaque
  `EString`s via `Ycs_eval`; real cmake handles them at generate time).
- Fragment-owned parser composition.
- Subdirectory scope enforcement (`add_subdirectory` records but does not
  isolate var / target scopes).
- Property scope expansion beyond target (global / source / test / cache).
- A purer functional-style function theory parallel to the cmake-style one
  (Y15 design space; revisit after F2 is in production).
- Property / random testing and formal proof.

## Notes

- Old production AST has no dedicated normal-variable `unset(NAME)`
  constructor. Normal unset-like behavior is encoded as `Yvar_set` with an
  empty value list. Dedicated unset constructors exist for cache / env only.
- `target_link_libraries`, `target_include_directories`, and
  `target_compile_definitions` preserve `PRIVATE` / `PUBLIC` / `INTERFACE`
  visibility, but do not model generator expressions or full transitive
  usage requirements yet.
