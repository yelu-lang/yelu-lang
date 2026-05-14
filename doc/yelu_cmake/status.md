# yelu_cmake — Status & Current Open Work

This doc tree (`doc/yelu_cmake/`) is cmake-language-specific.
Any future `yelu_shell` / `yelu_c` work would get its own
sibling tree.

Living tracker. Strip and update freely; durable design is in `design.md`,
code-anchored module guide in `structure.md`, history in
`../worklog_2026_04.md` / `../worklog_2026_05.md`.

## Where we are (2026-05-11)

**Retirement is essentially complete.** Production binaries
generate cmake text via `Yelu_cmake_utils → Yelu_cmake →
Yelu_cmake_emit → Lang_cmake_pp` with no calls into the legacy
bridge. The two languages — `yelu_cmake` (CMake-faithful) and
`yelu_cmake_normal` (normalized form) — have clean names
throughout `src/langs/yelu/`; the legacy stack lives in
`src/langs/yelu_legacy/` as reference-only.

**Verifications** (continuously green):
- `dune build && dune test` — all unit tests pass
- byte-equality oracle: `covered=194 uncovered=0`
- parser tests: 295 (incl. 125 pair-wise oracle cases across
  all 12 direct-parser families, genex included)
- `make cmake-only-check`: 12/12
- `make runcmake-yelu`: 50/50

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

**Remaining retirement items (E split):**
- **E1** — make legacy deadcode. Replace the byte oracle and
  pair-wise oracle with golden-file tests so neither references
  legacy. After E1: `yelu_legacy/` stays on disk but is
  unreached by any code or test.
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

## Known bridge shape gaps

Documented constructor-shape gaps where the legacy bridge raises
`Bridge_error` rather than silently dropping data. Production tests
don't exercise any of these today; each needs either a yelu_cmake IR
extension or a bridge-side rewrite. Locations refer to
`src/langs/yelu_legacy/yelu_cmake_legacy_bridge.ml`.

- **String-comparison conds beyond equality** — `Yexpr_str_less`,
  `Yexpr_str_greater`, `Yexpr_str_less_eq`, `Yexpr_str_greater_eq`
  (STRLESS / STRGREATER / STRLESS_EQUAL / STRGREATER_EQUAL) not yet
  mirrored in yelu_cmake.
- **`add_executable` / `add_library` with `EXCLUDE_FROM_ALL`** —
  bridge rejects the flag; yelu_cmake ctors don't carry the field.
- **`target_link_libraries` multi-target** — bridge supports exactly
  one target per call; production AST allows multiple. Either widen
  the yelu_cmake surface to take a target list, or have the bridge
  split into multiple per-target statements.
- **`add_custom_command(TARGET ...)`** — TARGET-form custom command
  deferred; production tests only use the OUTPUT-form variant.

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
