# yelu_tiny — Current Open Work

Living tracker. Strip and update freely; durable design is in `design.md`,
code-anchored module guide in `structure.md`, history in
`../worklog_2026_04.md` / `../worklog_2026_05.md`.

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

## What's open

| ID  | Title                            | Notes                                                                                                                                  |
| --- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| R3  | Genex theory                     | 0 / 34 production constructors mirrored. First slice should be the few generator expressions v2 / CMakeOnly steps actually use.        |
| R7  | (postponed) typecheck + wellform | Re-framed as **Y17** (see below). Carrying the production checker over straight is no longer the plan; tiny's theories deserve a fresh typing pass once yelu1↔cmake and yelu2↔yelu1 are stable. |
| —   | Macro elimination                | Deferred. Gated on R5 data + Bar #3 (real-world rewrites). Memo: `.claude/memory/project_macro_elimination.md`.                        |
| —   | Bar #3 — real-world cmake        | Rewrite z3 / llvm / torch builds in yelu; prove structural equivalence. Not started.                                                   |

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

`src/langs/yelu/fragments/` is retirable when:

- Every step file bridges (done at R1).
- Zero `_ -> fail` cases remain in the bridge (held at R2 for current scope).
- Production tests run through tiny with equivalent cmake output
  (done at R4 + R5 + R6).
- A workable typing pass exists in tiny (Y17, post-retirement).

At that point `src/langs/yelu_tiny/` becomes the production code and the
old `src/langs/yelu/` (sans parser / lexer / post-bridge stages) becomes
`src/langs/yelu_legacy/`.

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
