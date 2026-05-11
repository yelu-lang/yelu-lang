# yelu_tiny — Current Open Work

Living tracker. Strip and update freely; durable design is in `design.md`,
code-anchored module guide in `structure.md`, history in
`../worklog_2026_04.md` / `../worklog_2026_05.md`.

**Last verified 2026-05-11:** `dune build && dune test` green
(831 unit tests); byte-equality oracle covers 194/194 production
programs with 0 uncovered, 0 skipped. Parser tests (263 incl. 93
Phase 2a pair-wise: 3 var + 17 string + 14 list + 9 path + 11 file
+ 8 target + 6 dir + 7 find/install + 3 property + 6 cmake_op
scalar + 2 control + 7 cond) all flow through emit_ast without
falling back to direct emit. `make runcmake-yelu` green (50/50
pairs). Retirement Phase 1 done. Phase 2 warm-up trio landed.
Phase 2a covers all 12 families via separate Yelu1 parser
(`Yelu_parse_y1`) — var, string, list, path, file, target, dir,
property, find, install, cmake_op (scalar + control flow:
let/if/function/macro/while/foreach/break/continue/return/apply).
Pair-wise oracle agrees byte-for-byte on all 93 covered tests. Two
legacy-parser bugs surfaced (same shape: command that only matches
Ycs_string but receives Ycs_path / EVar fallback):
- `( set NAME val )` form
- `( policy_set "CMPxxxx" )` form
Both omitted from oracle; deferred. Phase 2a feature-complete.

## What's done

Three breadth milestones, in order of attempt:

- **Bar #1 — tutorial step parity.** v1 step1–step12 (root + math + table +
  config) all bridge through tiny; six configure through real cmake.
- **Bar #2 — theory breadth (lite).** All 14 production theories have at
  least a first slice (var, target, install, test, property, string, file,
  path, list, find, try, cmake_op, cond, dir). Genex stays deferred.
- **Retirement gluing — R1, R4, R5, R6.** Step files, `test_yelu_compile`
  (194), `test_runcmake_yelu` (50), and `test_yelu_parse` (170) all route
  through `bridge → tiny → cmake`. The 13 R4-b semantic-batch programs
  (block / return / while / break / continue / foreach_range /
  separate_arguments / macro) bridge through a probe-verified
  env-frame-stack model — see `../cmake/scope_and_control_flow.md`.
- **Retirement Phase 1 (done 2026-05-11).** Production lowering routes
  through `Yelu1 → emit_ast → Lang_cmake.exp → lang_cmake_pp → text`.
  Byte-equality oracle in `test_yelu_compile.ml` reports 194/194
  programs byte-identical with legacy `Lang_yelu_compile`. The
  `runcmake-yelu` suite (50 pairs) routes through the AST path.
  Three tiny IR extensions closed all bridge information-loss cases
  (`ECmakeForeachInList`; `before/system` fields on target_*; full
  `find_package` attribute set). Direct-text emit
  (`yelu_tiny_cmake_emit.ml`) is demoted to a diagnostic aid — kept
  callable for human inspection but not on the production path.
  Details: `retirement_plan.md`.

## What's open

| ID  | Title                            | Notes                                                                                                                                                                                           |
| --- | -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R3  | Genex theory (full)              | Production has 17 typed `Yge_*` ctors, but they're stringified at AST-build time via `yge` (`lang_yelu_utils.ml:7`), so the live production AST already carries opaque strings. Phase 2 warm-up landed `ECmakeGenex of string` as the bridge-side structural hook (commit TBD); full theory with eval semantics deferred until Phase 2c parser refactor reaches genex-heavy families. |
| R7  | (postponed) typecheck + wellform | Re-framed as **Y17** (see below). Carrying the production checker over straight is no longer the plan; tiny's theories deserve a fresh typing pass once yelu1↔cmake and yelu2↔yelu1 are stable. |
| —   | Macro elimination                | Deferred. Gated on R5 data + Bar #3 (real-world rewrites). Memo: `.claude/memory/project_macro_elimination.md`.                                                                                 |
| —   | Bar #3 — real-world cmake        | Rewrite z3 / llvm / torch builds in yelu; prove structural equivalence. Not started.                                                                                                            |

### Known bridge gaps (explicit fail cases, no production test hits them)

These are documented constructor-shape gaps where the bridge raises
`Bridge_error` with a descriptive message rather than silently dropping
data. Production tests do not exercise any of these today; each is a
future-work item that needs a tiny IR extension or bridge rewrite.

- **String-comparison conds beyond equality.** `Yexpr_str_less`,
  `Yexpr_str_greater`, `Yexpr_str_less_eq`, `Yexpr_str_greater_eq`
  (the STRLESS / STRGREATER / STRLESS_EQUAL / STRGREATER_EQUAL forms)
  not yet mirrored in tiny. See `yelu_cmake_to_yelu1.ml:64`.
- **`add_executable` / `add_library` with `EXCLUDE_FROM_ALL`.** Bridge
  rejects the flag at `:743` and `:752`; tiny surface ctors don't
  carry the field. Extending the ctors is straightforward when needed.
- **`target_link_libraries` multi-target.** Bridge supports exactly
  one target per call (`yelu_cmake_to_yelu1.ml:774`); production AST
  allows multiple in a single statement. Surface either takes a list
  or the bridge splits into multiple per-target ECmake* statements.
- **`add_custom_command(TARGET ...)`.** TARGET-form custom command
  deferred — production tests use the OUTPUT-form variant. See
  `yelu_cmake_to_yelu1.ml:900`.

## Y17 — types-on-tiny (post-retirement)

The previous typing attempt (production `Stage_typecheck` per fragment) was
structurally shallow: each fragment validated its own expression types in
isolation, with `wellform` bolted on top to handle cross-theory name
binding. With proper theories (yelu_theory_*) the type design has actual
semantic ground to stand on — namespace separation is already in `env`,
mutability / set-once / identity rules belong with each theory module, and
the lift/lower pair gives a natural place to push richer invariants.

Order: bring types in **after** retirement establishes yelu1↔cmake and
yelu2↔yelu1 as a stable composition. Retrofitting types onto an unstable
substrate would repeat the previous failure mode.

## Retirement criterion

> Full plan: `retirement_plan.md`. The summary below states the gate;
> the plan covers the two-phase sequencing (emit-through-cmake-AST,
> then parser-produces-Yelu1) and the oracle test that keeps legacy
> compile callable forever.

Retirement is bridge + emit parity only; typing decisions (Y17) happen
*after* retirement, on the renamed-yelu codebase. `src/langs/yelu/` is
retirable when:

- Every step file bridges (done at R1).
- Zero unguarded `_ -> fail` cases remain in the bridge (R2 — three
  catch-alls still document attrition-surface gaps; production tests do
  not hit them today).
- Production tests run through tiny with equivalent cmake output
  (done at R4 + R5 + R6).
- R3 (genex first slice) lands so v2 / CMakeOnly genex usage is
  bridge-faithful, not catch-all-stubbed.

At that point `src/langs/yelu_tiny/` becomes the production code and the
old `src/langs/yelu/` (sans parser / lexer / post-bridge stages) becomes
`src/langs/yelu_legacy/`. Legacy deletion is a separate later decision
gated on Y17 — keep `yelu_legacy` around as a comparison baseline until
the typing model is settled.

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
3. **Move emit / translate arms closer to each fragment.** Currently
   `yelu_tiny_translate.ml` (1.7 k lines) and `yelu_tiny_cmake_emit.ml`
   (964 lines) are central registries — they work, but entropy returns
   here as constructors land. Per-fragment translate / emit modules
   reverse the trend. Cosmetic, not load-bearing; defer until after
   the bigger Y17 typing decisions.
4. **Y17 — fresh typing pass on tiny** (see below).
5. **Promote compat surfaces to real theories** where they're worth it
   (genex first, then find / try / cmake_op subsets). This pairs with
   Y17 — typing decisions inform which surfaces deserve the lift.

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
